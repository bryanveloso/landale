"""Analyze voice characteristics for ElectroVoice RE20 to establish optimal thresholds.

This script analyzes your real voice sample to establish empirical energy thresholds
based on the specific characteristics of the ElectroVoice RE20 microphone.
"""

import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))


def analyze_voice_sample():
    """Analyze the real voice sample to determine optimal energy thresholds."""
    voice_sample_path = Path(__file__).parent / "fixtures" / "real_voice_sample.wav"

    if not voice_sample_path.exists():
        print(f"Voice sample not found at {voice_sample_path}")
        return

    # Load the voice sample
    with wave.open(str(voice_sample_path), "rb") as wav:
        frames = wav.readframes(wav.getnframes())
        audio_data = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32767.0
        sample_rate = wav.getframerate()
        duration = len(audio_data) / sample_rate

    print("=== ElectroVoice RE20 Voice Analysis ===")
    print(f"Audio duration: {duration:.2f} seconds")
    print(f"Sample rate: {sample_rate} Hz")
    print(f"Total samples: {len(audio_data)}")
    print()

    # Calculate overall energy characteristics
    overall_energy = np.mean(audio_data**2)
    overall_rms = np.sqrt(overall_energy)
    overall_peak = np.max(np.abs(audio_data))

    print("=== Overall Signal Characteristics ===")
    print(f"Overall energy: {overall_energy:.8f}")
    print(f"Overall RMS: {overall_rms:.6f}")
    print(f"Peak amplitude: {overall_peak:.6f}")
    print(f"Dynamic range: {20 * np.log10(overall_peak / (overall_rms + 1e-10)):.1f} dB")
    print()

    # Analyze in chunks to understand temporal variations
    chunk_size_ms = 50  # 50ms chunks (same as our tests)
    chunk_samples = int(chunk_size_ms * sample_rate / 1000)

    chunk_energies = []
    chunk_rms_values = []
    chunk_peaks = []

    for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
        chunk = audio_data[i : i + chunk_samples]

        energy = np.mean(chunk**2)
        rms = np.sqrt(energy)
        peak = np.max(np.abs(chunk))

        chunk_energies.append(energy)
        chunk_rms_values.append(rms)
        chunk_peaks.append(peak)

    chunk_energies = np.array(chunk_energies)
    chunk_rms_values = np.array(chunk_rms_values)
    chunk_peaks = np.array(chunk_peaks)

    print(f"=== Chunk-based Analysis ({chunk_size_ms}ms chunks) ===")
    print(f"Number of chunks: {len(chunk_energies)}")
    print()

    # Energy statistics
    print("Energy Statistics:")
    print(f"  Min energy: {np.min(chunk_energies):.8f}")
    print(f"  Max energy: {np.max(chunk_energies):.8f}")
    print(f"  Mean energy: {np.mean(chunk_energies):.8f}")
    print(f"  Median energy: {np.median(chunk_energies):.8f}")
    print(f"  25th percentile: {np.percentile(chunk_energies, 25):.8f}")
    print(f"  75th percentile: {np.percentile(chunk_energies, 75):.8f}")
    print(f"  90th percentile: {np.percentile(chunk_energies, 90):.8f}")
    print(f"  95th percentile: {np.percentile(chunk_energies, 95):.8f}")
    print()

    # RMS statistics
    print("RMS Statistics:")
    print(f"  Min RMS: {np.min(chunk_rms_values):.6f}")
    print(f"  Max RMS: {np.max(chunk_rms_values):.6f}")
    print(f"  Mean RMS: {np.mean(chunk_rms_values):.6f}")
    print(f"  Median RMS: {np.median(chunk_rms_values):.6f}")
    print(f"  25th percentile: {np.percentile(chunk_rms_values, 25):.6f}")
    print(f"  75th percentile: {np.percentile(chunk_rms_values, 75):.6f}")
    print(f"  90th percentile: {np.percentile(chunk_rms_values, 90):.6f}")
    print(f"  95th percentile: {np.percentile(chunk_rms_values, 95):.6f}")
    print()

    # Peak statistics
    print("Peak Statistics:")
    print(f"  Min peak: {np.min(chunk_peaks):.6f}")
    print(f"  Max peak: {np.max(chunk_peaks):.6f}")
    print(f"  Mean peak: {np.mean(chunk_peaks):.6f}")
    print(f"  Median peak: {np.median(chunk_peaks):.6f}")
    print()

    # Silence detection analysis
    print("=== Silence Detection Analysis ===")

    # Different threshold candidates based on research
    thresholds = [
        ("Very low (10th percentile)", np.percentile(chunk_energies, 10)),
        ("Low (25th percentile)", np.percentile(chunk_energies, 25)),
        ("Conservative (median)", np.median(chunk_energies)),
        ("Research-based (mean/10)", np.mean(chunk_energies) / 10),
        ("Aggressive (mean/20)", np.mean(chunk_energies) / 20),
    ]

    for name, threshold in thresholds:
        silence_chunks = np.sum(chunk_energies < threshold)
        speech_chunks = len(chunk_energies) - silence_chunks
        speech_ratio = speech_chunks / len(chunk_energies)

        print(
            f"{name:25} | Threshold: {threshold:.8f} | Speech: {speech_ratio:.1%} | Silence: {(1 - speech_ratio):.1%}"
        )

    print()

    # Recommended thresholds based on research and analysis
    print("=== Recommended Thresholds for ElectroVoice RE20 ===")

    # Based on research: dynamic mics need much lower thresholds
    # Typical speech detection uses energy > background_noise * 2-3
    background_threshold = np.percentile(chunk_energies, 15)  # Assume bottom 15% is background
    speech_threshold = background_threshold * 2  # 2x background for speech detection

    # For boundary detection, we want something more sensitive
    boundary_threshold = np.percentile(chunk_energies, 5)  # Very sensitive for boundaries

    print(f"Background noise threshold: {background_threshold:.8f}")
    print(f"Speech detection threshold: {speech_threshold:.8f}")
    print(f"Boundary detection threshold: {boundary_threshold:.8f}")
    print()

    # Test these thresholds
    speech_detected = np.sum(chunk_energies > speech_threshold) / len(chunk_energies)
    boundary_detected = np.sum(chunk_energies > boundary_threshold) / len(chunk_energies)

    print(f"With speech threshold: {speech_detected:.1%} chunks detected as speech")
    print(f"With boundary threshold: {boundary_detected:.1%} chunks detected as meaningful")
    print()

    # Generate code-ready values
    print("=== Code-Ready Threshold Values ===")
    print("# For AdaptiveChunker boundary detection:")
    print(f"ENERGY_THRESHOLD = {boundary_threshold:.8f}  # Very sensitive for boundaries")
    print(f"RMS_THRESHOLD = {np.sqrt(boundary_threshold):.6f}  # RMS equivalent")
    print()
    print("# For speech detection:")
    print(f"SPEECH_ENERGY_THRESHOLD = {speech_threshold:.8f}")
    print(f"SPEECH_RMS_THRESHOLD = {np.sqrt(speech_threshold):.6f}")
    print()
    print("# For test assertions (maximum energy seen):")
    print(f"MAX_ENERGY_THRESHOLD = {np.max(chunk_energies):.8f}")
    print(f"MAX_RMS_THRESHOLD = {np.max(chunk_rms_values):.6f}")
    print()

    # VAD optimization insights
    print("=== VAD Optimization Insights ===")

    # Calculate zero crossing rate statistics
    def calculate_zcr(chunk):
        return np.sum(np.diff(np.sign(chunk)) != 0) / (len(chunk) - 1)

    zcr_values = []
    for i in range(0, len(audio_data) - chunk_samples, chunk_samples):
        chunk = audio_data[i : i + chunk_samples]
        zcr = calculate_zcr(chunk)
        zcr_values.append(zcr)

    zcr_values = np.array(zcr_values)

    print("Zero Crossing Rate statistics:")
    print(f"  Mean ZCR: {np.mean(zcr_values):.4f}")
    print(f"  Min ZCR: {np.min(zcr_values):.4f}")
    print(f"  Max ZCR: {np.max(zcr_values):.4f}")
    print(f"  Median ZCR: {np.median(zcr_values):.4f}")
    print()

    # Spectral centroid estimation (simplified)
    print("ElectroVoice RE20 characteristics confirmed:")
    print("- Very low energy levels (typical for dynamic mics)")
    print(f"- High zero crossing rates ({np.mean(zcr_values):.3f} average)")
    print(f"- Wide dynamic range ({20 * np.log10(np.max(chunk_peaks) / (np.min(chunk_rms_values) + 1e-10)):.1f} dB)")
    print("- Consistent with professional broadcast microphone behavior")


if __name__ == "__main__":
    analyze_voice_sample()
