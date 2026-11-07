#!/usr/bin/env python3
"""
NetGet Sound Generator
Generates 4 lightweight mono PCM WAV sounds using pure Python stdlib (no ffmpeg).
All sounds are under 0.8 seconds and under 40 KB.
"""

import math
import os
import struct
import wave

SAMPLE_RATE = 22050  # 22.05 kHz mono 16-bit gives crisp sounds with tiny file size (~44 KB/s)

def write_wav(file_path: str, samples: list[float]):
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with wave.open(file_path, 'wb') as wav:
        wav.setnchannels(1)  # Mono
        wav.setsampwidth(2)  # 16-bit
        wav.setframerate(SAMPLE_RATE)
        # Pack float [-1.0, 1.0] to signed 16-bit int [-32767, 32767]
        raw_bytes = bytearray()
        for s in samples:
            clamped = max(-1.0, min(1.0, s))
            val = int(clamped * 32760)
            raw_bytes.extend(struct.pack('<h', val))
        wav.writeframes(raw_bytes)
    size_kb = os.path.getsize(file_path) / 1024
    print(f"Generated {os.path.basename(file_path)}: {len(samples)/SAMPLE_RATE:.2f}s, {size_kb:.1f} KB")

def generate_soft_pop(duration: float = 0.12) -> list[float]:
    """Short soft pop for start/add: pitch glides down with quick exponential decay."""
    total_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(total_samples):
        t = i / SAMPLE_RATE
        # Exponential envelope
        decay = math.exp(-35 * t)
        freq = 600 - (400 * (t / duration))
        val = math.sin(2 * math.pi * freq * t) * decay * 0.7
        samples.append(val)
    return samples

def generate_rising_chime(duration: float = 0.35) -> list[float]:
    """Rising two-note chime for completed (C6 -> G6)."""
    samples = []
    note1_dur = 0.16
    note2_dur = 0.19
    
    # Note 1: 1046.5 Hz (C6)
    n1_samples = int(SAMPLE_RATE * note1_dur)
    for i in range(n1_samples):
        t = i / SAMPLE_RATE
        decay = math.exp(-12 * t)
        val = math.sin(2 * math.pi * 1046.5 * t) * decay * 0.6
        # Slight harmonic
        val += math.sin(2 * math.pi * 2093.0 * t) * decay * 0.2
        samples.append(val)

    # Note 2: 1567.98 Hz (G6)
    n2_samples = int(SAMPLE_RATE * note2_dur)
    for i in range(n2_samples):
        t = i / SAMPLE_RATE
        decay = math.exp(-10 * t)
        val = math.sin(2 * math.pi * 1567.98 * t) * decay * 0.7
        val += math.sin(2 * math.pi * 3135.96 * t) * decay * 0.25
        samples.append(val)
        
    return samples

def generate_low_double_tone(duration: float = 0.38) -> list[float]:
    """Low double tone for failed (two minor falling pulses: 320 Hz -> 220 Hz)."""
    samples = []
    pulse1 = int(SAMPLE_RATE * 0.18)
    for i in range(pulse1):
        t = i / SAMPLE_RATE
        decay = math.exp(-14 * t)
        val = (math.sin(2 * math.pi * 330.0 * t) + 0.3 * math.sin(2 * math.pi * 660.0 * t)) * decay * 0.7
        samples.append(val)
        
    pulse2 = int(SAMPLE_RATE * 0.20)
    for i in range(pulse2):
        t = i / SAMPLE_RATE
        decay = math.exp(-10 * t)
        val = (math.sin(2 * math.pi * 220.0 * t) + 0.3 * math.sin(2 * math.pi * 440.0 * t)) * decay * 0.8
        samples.append(val)
        
    return samples

def generate_three_note_flourish(duration: float = 0.55) -> list[float]:
    """Three-note flourish for queue finished (E5 -> G5 -> C6)."""
    samples = []
    notes = [
        (659.25, 0.15),   # E5
        (783.99, 0.15),   # G5
        (1046.50, 0.25),  # C6
    ]
    for freq, dur in notes:
        n_samples = int(SAMPLE_RATE * dur)
        for i in range(n_samples):
            t = i / SAMPLE_RATE
            decay = math.exp(-8 * t)
            val = math.sin(2 * math.pi * freq * t) * decay * 0.65
            val += math.sin(2 * math.pi * (freq * 2) * t) * decay * 0.2
            samples.append(val)
    return samples

def main():
    target_dir = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res', 'raw')
    os.makedirs(target_dir, exist_ok=True)
    
    write_wav(os.path.join(target_dir, 'sound_start.wav'), generate_soft_pop())
    write_wav(os.path.join(target_dir, 'sound_complete.wav'), generate_rising_chime())
    write_wav(os.path.join(target_dir, 'sound_failed.wav'), generate_low_double_tone())
    write_wav(os.path.join(target_dir, 'sound_queue_done.wav'), generate_three_note_flourish())
    print("Sound generation complete.")

if __name__ == '__main__':
    main()
