"""Microphone profile system for adaptive audio processing.

Centralizes microphone-specific characteristics and thresholds to make
the system adaptable to different microphones without code changes.
"""

from dataclasses import dataclass
from typing import Any


@dataclass
class MicrophoneProfile:
    """Profile containing microphone-specific audio characteristics."""

    # Basic microphone info
    manufacturer: str
    model: str
    microphone_type: str  # "dynamic", "condenser", "ribbon"

    # Energy characteristics (empirically determined)
    min_energy_threshold: float  # 5th percentile - nearly silent
    background_noise_threshold: float  # 15th percentile - background noise floor
    speech_detection_threshold: float  # 2x background - reliable speech detection
    boundary_detection_threshold: float  # Very sensitive for chunk boundaries
    max_energy_threshold: float  # Maximum observed energy

    # RMS characteristics
    min_rms_threshold: float
    speech_rms_threshold: float
    max_rms_threshold: float

    # VAD-specific parameters
    vad_threshold: float  # Speech probability threshold
    vad_sensitivity: float  # Multiplier for low-gain microphones
    noise_suppression: bool  # Enable noise suppression algorithms

    # Spectral characteristics
    expected_zcr_mean: float  # Average zero crossing rate
    expected_zcr_range: tuple[float, float]  # Min, max ZCR
    spectral_centroid_range: tuple[float, float]  # Expected frequency range

    # Dynamic range and gain
    dynamic_range_db: float
    requires_high_gain: bool  # True for low-output mics like RE20
    gain_requirement_db: float  # Typical gain requirement

    # Test assertion thresholds
    test_energy_threshold: float  # For meaningful audio in tests
    test_rms_threshold: float  # For test RMS assertions
    test_window_energy_threshold: float  # For sliding window tests

    # Processing optimization hints
    chunk_size_preference: str  # "small", "medium", "large"
    latency_tolerance: str  # "low", "medium", "high"
    noise_environment: str  # "studio", "broadcast", "streaming", "field"


# Pre-configured microphone profiles
MICROPHONE_PROFILES: dict[str, MicrophoneProfile] = {
    "electrovoice_re20": MicrophoneProfile(
        # Basic info
        manufacturer="ElectroVoice",
        model="RE20",
        microphone_type="dynamic",
        # Energy characteristics (from empirical analysis)
        min_energy_threshold=0.00000000,  # 5th percentile
        background_noise_threshold=0.00000007,  # 15th percentile
        speech_detection_threshold=0.00000013,  # 2x background
        boundary_detection_threshold=0.000001,  # Very sensitive for boundaries
        max_energy_threshold=0.00457588,  # Maximum observed
        # RMS characteristics
        min_rms_threshold=0.000015,
        speech_rms_threshold=0.000362,
        max_rms_threshold=0.067645,
        # VAD parameters optimized for RE20
        vad_threshold=0.1,  # Lower threshold for low-output dynamic mic
        vad_sensitivity=1.5,  # Higher sensitivity multiplier
        noise_suppression=True,  # Enable for broadcast environment
        # Spectral characteristics (from analysis)
        expected_zcr_mean=0.9715,
        expected_zcr_range=(0.4460, 1.0000),
        spectral_centroid_range=(200.0, 4000.0),  # Broad range for natural speech
        # Dynamic range and gain
        dynamic_range_db=83.8,  # Wide dynamic range
        requires_high_gain=True,  # RE20 needs significant gain
        gain_requirement_db=60.0,  # Typical 50-70dB gain requirement
        # Test thresholds (updated from speech-only analysis, excluding initial silence)
        test_energy_threshold=0.00000457,  # 10th percentile of actual speech - catches low-energy speech
        test_rms_threshold=0.000677,  # Square root of 10th percentile energy
        test_window_energy_threshold=0.00003204,  # 25th percentile - good for window validation
        # Processing hints
        chunk_size_preference="small",  # Better for low-latency streaming
        latency_tolerance="low",  # Streaming/broadcast application
        noise_environment="streaming",  # Gaming/streaming setup
    ),
    # Template for other microphones
    "generic_condenser": MicrophoneProfile(
        manufacturer="Generic",
        model="Condenser",
        microphone_type="condenser",
        # Higher energy levels typical for condenser mics
        min_energy_threshold=0.00001,
        background_noise_threshold=0.0001,
        speech_detection_threshold=0.001,
        boundary_detection_threshold=0.0005,
        max_energy_threshold=0.1,
        min_rms_threshold=0.001,
        speech_rms_threshold=0.01,
        max_rms_threshold=0.3,
        vad_threshold=0.5,  # Higher threshold for higher-output condenser
        vad_sensitivity=1.0,
        noise_suppression=False,
        expected_zcr_mean=0.5,
        expected_zcr_range=(0.1, 0.8),
        spectral_centroid_range=(500.0, 3000.0),
        dynamic_range_db=120.0,
        requires_high_gain=False,
        gain_requirement_db=30.0,
        test_energy_threshold=0.001,
        test_rms_threshold=0.01,
        test_window_energy_threshold=0.005,
        chunk_size_preference="medium",
        latency_tolerance="medium",
        noise_environment="studio",
    ),
}


class MicrophoneProfileManager:
    """Manager for microphone profiles and adaptive thresholds."""

    def __init__(self, profile_name: str = "electrovoice_re20"):
        """Initialize with a specific microphone profile."""
        if profile_name not in MICROPHONE_PROFILES:
            raise ValueError(f"Unknown microphone profile: {profile_name}")

        self.profile = MICROPHONE_PROFILES[profile_name]
        self.profile_name = profile_name

    def get_vad_config(self) -> dict[str, Any]:
        """Get VAD configuration optimized for this microphone."""
        return {
            "threshold": self.profile.vad_threshold,
            "noise_suppression": self.profile.noise_suppression,
            "sensitivity_multiplier": self.profile.vad_sensitivity,
        }

    def get_adaptive_chunker_config(self) -> dict[str, Any]:
        """Get adaptive chunker configuration for this microphone."""
        return {
            "vad_threshold": self.profile.vad_threshold,
            "speech_boundary_tolerance_ms": 200 if self.profile.latency_tolerance == "low" else 300,
            "silence_extension_ms": 100 if self.profile.requires_high_gain else 150,
        }

    def get_test_thresholds(self) -> dict[str, float]:
        """Get test assertion thresholds for this microphone."""
        return {
            "energy_threshold": self.profile.test_energy_threshold,
            "rms_threshold": self.profile.test_rms_threshold,
            "window_energy_threshold": self.profile.test_window_energy_threshold,
            "speech_detection_threshold": self.profile.speech_detection_threshold,
        }

    def get_processing_hints(self) -> dict[str, Any]:
        """Get processing optimization hints for this microphone."""
        return {
            "chunk_size_preference": self.profile.chunk_size_preference,
            "latency_tolerance": self.profile.latency_tolerance,
            "requires_high_gain": self.profile.requires_high_gain,
            "noise_environment": self.profile.noise_environment,
        }

    def is_energy_meaningful(self, energy: float) -> bool:
        """Check if energy level indicates meaningful audio content."""
        return energy > self.profile.boundary_detection_threshold

    def is_speech_detected(self, energy: float) -> bool:
        """Check if energy level indicates speech."""
        return energy > self.profile.speech_detection_threshold

    def is_background_noise(self, energy: float) -> bool:
        """Check if energy level is likely background noise."""
        return energy <= self.profile.background_noise_threshold

    def get_microphone_info(self) -> str:
        """Get human-readable microphone information."""
        return f"{self.profile.manufacturer} {self.profile.model} ({self.profile.microphone_type})"

    def export_analysis_summary(self) -> str:
        """Export analysis summary for documentation."""
        return f"""
Microphone Profile: {self.get_microphone_info()}
=====================================

Energy Characteristics:
- Background noise: {self.profile.background_noise_threshold:.8f}
- Speech detection: {self.profile.speech_detection_threshold:.8f}
- Boundary detection: {self.profile.boundary_detection_threshold:.8f}
- Maximum observed: {self.profile.max_energy_threshold:.8f}

RMS Characteristics:
- Minimum: {self.profile.min_rms_threshold:.6f}
- Speech level: {self.profile.speech_rms_threshold:.6f}
- Maximum: {self.profile.max_rms_threshold:.6f}

VAD Configuration:
- Threshold: {self.profile.vad_threshold}
- Sensitivity: {self.profile.vad_sensitivity}x
- Noise suppression: {self.profile.noise_suppression}

Spectral Characteristics:
- Zero crossing rate: {self.profile.expected_zcr_mean:.3f} (range: {self.profile.expected_zcr_range})
- Spectral centroid: {self.profile.spectral_centroid_range[0]:.0f}-{self.profile.spectral_centroid_range[1]:.0f} Hz

Technical Specifications:
- Dynamic range: {self.profile.dynamic_range_db:.1f} dB
- Gain requirement: {self.profile.gain_requirement_db:.0f} dB
- High gain required: {self.profile.requires_high_gain}

Optimization:
- Environment: {self.profile.noise_environment}
- Latency tolerance: {self.profile.latency_tolerance}
- Chunk preference: {self.profile.chunk_size_preference}
"""


# Global instance for current microphone (can be changed at runtime)
current_microphone = MicrophoneProfileManager("electrovoice_re20")


def set_microphone_profile(profile_name: str) -> None:
    """Change the active microphone profile."""
    global current_microphone
    current_microphone = MicrophoneProfileManager(profile_name)


def get_current_microphone() -> MicrophoneProfileManager:
    """Get the currently active microphone profile manager."""
    return current_microphone
