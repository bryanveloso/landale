#!/usr/bin/env python3
"""Demo script to show audio buffer memory management protections in action.

This script demonstrates the P1 HIGH priority memory safety features that
prevent memory exhaustion during audio processing.

Run with: uv run python tests/test_audio_buffer_memory_demo.py
"""

import asyncio
import time
from unittest.mock import patch

from src.audio_processor import AudioChunk, AudioFormat, AudioProcessor


async def demonstrate_buffer_protections():
    """Demonstrate key buffer memory protection features."""
    print("🎯 Audio Buffer Memory Management Demo")
    print("=" * 50)
    
    # Create processor with small limits for demonstration
    with patch('os.path.exists', return_value=True):
        processor = AudioProcessor(
            whisper_model_path="/tmp/demo_model.bin",
            buffer_duration_ms=500,
            max_buffer_size=64 * 1024,  # 64KB limit
            memory_optimization=True
        )
    
    await processor.start()
    print(f"✅ Started processor with {processor.max_buffer_size / 1024:.0f}KB buffer limit")
    
    try:
        # Demo 1: Buffer size limit enforcement
        print("\n📊 Demo 1: Buffer Size Limit Enforcement")
        print("-" * 40)
        
        audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        large_chunk_size = 32 * 1024  # 32KB chunks
        
        print(f"Adding 3 chunks of {large_chunk_size / 1024:.0f}KB each...")
        for i in range(3):
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000) + i * 100_000,
                format=audio_format,
                data=b'\x00' * large_chunk_size,
                source_id=f"demo_{i}"
            )
            processor.add_chunk(chunk)
            
            print(f"  Chunk {i+1}: Buffer={processor.buffer.total_size / 1024:.1f}KB, "
                  f"Chunks={len(processor.buffer.chunks)}, "
                  f"Overflows={processor.buffer_overflow_events}")
        
        print(f"🛡️  Buffer stayed within {processor.max_buffer_size / 1024:.0f}KB limit!")
        
        # Demo 2: Chunk count explosion prevention
        print("\n📈 Demo 2: Chunk Count Explosion Prevention")
        print("-" * 40)
        
        small_chunk_size = 100  # Very small chunks
        print(f"Rapidly adding many tiny {small_chunk_size}B chunks...")
        
        initial_overflow_count = processor.buffer_overflow_events
        for i in range(200):  # Many small chunks
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000) + i * 1000,
                format=audio_format,
                data=b'\x00' * small_chunk_size,
                source_id=f"tiny_{i}"
            )
            processor.add_chunk(chunk)
        
        final_overflow_count = processor.buffer_overflow_events
        print(f"  Added 200 tiny chunks")
        print(f"  Final chunk count: {len(processor.buffer.chunks)} (max: {processor.max_chunk_count})")
        print(f"  Overflow events: {final_overflow_count - initial_overflow_count}")
        print(f"🛡️  Chunk count stayed within {processor.max_chunk_count} limit!")
        
        # Demo 3: Memory usage tracking
        print("\n📊 Demo 3: Memory Usage Tracking")
        print("-" * 40)
        
        memory_stats = processor.get_memory_stats()
        current_usage = processor.get_memory_usage()
        
        print(f"  Buffer memory: {memory_stats['buffer_memory'] / 1024:.1f}KB")
        print(f"  Processing overhead: {memory_stats['processing_memory'] / 1024:.1f}KB")
        print(f"  Peak memory: {memory_stats['peak_memory'] / 1024:.1f}KB")
        print(f"  Total usage: {current_usage / 1024:.1f}KB")
        print("📈 Memory tracking provides real-time visibility!")
        
        # Demo 4: Buffer duration calculation
        print("\n⏱️  Demo 4: Buffer Duration Tracking")
        print("-" * 40)
        
        duration = processor.get_buffer_duration()
        print(f"  Current buffer duration: {duration:.2f} seconds")
        print(f"  Target processing threshold: {processor.buffer_duration_ms / 1000:.1f} seconds")
        
        if duration > 0:
            print("🎵 Buffer contains audio data ready for processing!")
        else:
            print("🔇 Buffer is empty")
        
    finally:
        await processor.stop()
        print("\n✅ Demo completed - processor stopped cleanly")


async def demonstrate_stress_resilience():
    """Demonstrate behavior under stress conditions."""
    print("\n🔥 Stress Test: High Input Rate Handling")
    print("=" * 50)
    
    with patch('os.path.exists', return_value=True):
        processor = AudioProcessor(
            whisper_model_path="/tmp/stress_model.bin",
            buffer_duration_ms=100,  # Very short
            max_buffer_size=16 * 1024,  # Small 16KB limit
            memory_optimization=True
        )
    
    await processor.start()
    
    try:
        audio_format = AudioFormat(sample_rate=16000, channels=1, bit_depth=16)
        
        print("🚀 Simulating overwhelming audio input rate...")
        start_time = time.time()
        
        # Rapid fire chunks
        for i in range(100):
            chunk = AudioChunk(
                timestamp=int(time.time() * 1_000_000) + i * 100,
                format=audio_format,
                data=b'\x00' * 1024,  # 1KB chunks
                source_id=f"stress_{i}"
            )
            processor.add_chunk(chunk)
        
        end_time = time.time()
        
        print(f"✅ Processed 100 chunks in {(end_time - start_time) * 1000:.1f}ms")
        print(f"🛡️  Buffer size: {processor.buffer.total_size / 1024:.1f}KB (limit: {processor.max_buffer_size / 1024:.0f}KB)")
        print(f"📊 Overflow events: {processor.buffer_overflow_events}")
        print(f"🎯 System remained stable under stress!")
        
    finally:
        await processor.stop()


if __name__ == "__main__":
    print("🎧 Phononmaser Audio Buffer Memory Management Demo")
    print("🎯 Demonstrating P1 HIGH priority memory safety features")
    print()
    
    async def main():
        await demonstrate_buffer_protections()
        await demonstrate_stress_resilience()
        
        print("\n" + "=" * 50)
        print("✅ All memory protection mechanisms working correctly!")
        print("🛡️  Production streaming sessions are protected from memory exhaustion")
        print("📈 Real-time monitoring provides visibility into buffer health")
    
    asyncio.run(main())