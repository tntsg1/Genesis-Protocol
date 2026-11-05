"""Ambient score for GENESIS PROTOCOL, composed from recorded material in the
Sonniss library (no oscillators): stretched pads as the bed, a pentatonic
drone motif placed sparsely, harp glints, granular air, long reverb; every
source is tuned to one key by detecting its fundamental. Each scene track is
rendered a little long and its tail crossfaded into its head, so it loops
without a seam. Also cuts and levels the sound effects.

Run: G:/audio_library/venv/Scripts/python.exe tools/compose_music.py
Writes assets/audio/music/*.ogg and assets/audio/sfx/*.ogg (via ffmpeg).
"""
import os
import subprocess
import numpy as np
import soundfile as sf
from pedalboard import Pedalboard, Reverb, LowpassFilter, HighpassFilter, Gain, Compressor, time_stretch
from pedalboard.io import AudioFile

LIB = "G:/audio_library/sonniss/files/"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
TMP = "G:/audio_library/work/genesis"
FFMPEG = "C:/ProgramData/chocolatey/bin/ffmpeg"
SR = 48000
rng = np.random.default_rng(20261028)

SRC = {
    "pad": "CB Sound Design - Dreamcatcher - The Sound of Dreams & Magic/Synth_Pad_12.wav",
    "ice": "David Dumais Audio - Ice & Frost Magic 1/Magic_Ambience_Ice05.wav",
    "ice2": "David Dumais Audio - Magic Sound FX Pack 1/Magic_Ambience_Ice09.wav",
    "drone": "Eiravaein Sound - Yvaine/Yvaine,drone,electric,Pentatonic,DI,position7,light,oceanic,euphoric,interference.wav",
    "harp": "CB Sound Design - Dreamcatcher - The Sound of Dreams & Magic/Harp_Glissando_10b.wav",
    "air": "Glitchedtones - Dreamstates/Granular Abstract Ambient Element (12).wav",
    "air2": "Glitchedtones - Dreamstates/Granular Abstract Ambient Element (25).wav",
    "dark": "Doex Studio - Qantum UI/UI_BACKGROUND_LOW_DarkDrone_01.wav",
}


def load(name):
    with AudioFile(LIB + SRC[name]).resampled_to(SR) as f:
        a = f.read(f.frames)
    if a.shape[0] == 1:
        a = np.vstack([a, a])
    return a[:2].astype(np.float32)


def fundamental(a):
    """Strongest spectral peak between 70 and 900 Hz (Hz)."""
    m = a.mean(axis=0)
    n = min(len(m), SR * 6)
    seg = m[:n] * np.hanning(n)
    spec = np.abs(np.fft.rfft(seg))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    band = (freqs > 70) & (freqs < 900)
    return float(freqs[band][np.argmax(spec[band])])


def to_key(a, key_hz):
    """Semitones that bring the source's fundamental onto the key (nearest octave)."""
    f = fundamental(a)
    st = 12.0 * np.log2(key_hz / f)
    return float(st - 12.0 * round(st / 12.0))


def stretch(a, factor, semis):
    return time_stretch(a, SR, stretch_factor=factor, pitch_shift_in_semitones=semis).astype(np.float32)


def env(n, attack, release):
    e = np.ones(n, np.float32)
    a = min(int(attack * SR), n // 2)
    r = min(int(release * SR), n // 2)
    e[:a] = np.linspace(0, 1, a) ** 2
    e[n - r:] = np.linspace(1, 0, r) ** 2
    return e


def place(track, clip, at, gain_db, pan):
    i = int(at * SR)
    if i >= track.shape[1]:
        return
    n = min(clip.shape[1], track.shape[1] - i)
    g = 10 ** (gain_db / 20.0)
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    track[0, i:i + n] += clip[0, :n] * g * l * 1.414
    track[1, i:i + n] += clip[1, :n] * g * r * 1.414


def active(a, floor_db=-30.0):
    """The part of a sample louder than floor_db under its own peak level."""
    m = np.abs(a).mean(axis=0)
    w = int(0.1 * SR)
    lv = np.convolve(m, np.ones(w) / w, mode="same")
    on = np.where(lv > lv.max() * 10 ** (floor_db / 20.0))[0]
    return a[:, on[0]:on[-1]] if len(on) > SR else a


def bed_layer(src, key_hz, length, interval, gain_db, factor=0.25, offset=0.0):
    a = active(load(src))
    semis = to_key(a, key_hz) + interval
    s = stretch(a, factor, semis)
    # Tile with long, equal-power crossfades, so the bed never thins out.
    out = np.zeros((2, int(length * SR)), np.float32)
    xf = min(int(10 * SR), s.shape[1] // 3)
    step = s.shape[1] - xf
    clip = s.copy()
    clip[:, :xf] *= np.sin(np.linspace(0, np.pi / 2, xf))
    clip[:, -xf:] *= np.cos(np.linspace(0, np.pi / 2, xf))
    pos = -int(offset * SR)
    while pos < out.shape[1]:
        a0 = max(0, -pos)
        n = min(clip.shape[1] - a0, out.shape[1] - max(pos, 0))
        if n > 0:
            out[:, max(pos, 0):max(pos, 0) + n] += clip[:, a0:a0 + n]
        pos += step
    return out * 10 ** (gain_db / 20.0)


def compose(name, key_hz, length, motif_gap, motif_db, glint_gap, register, dark=False, air_db=-26.0):
    total = length + 8.0
    t = np.zeros((2, int(total * SR)), np.float32)
    t += bed_layer("pad", key_hz, total, 0, -12)
    t += bed_layer("ice", key_hz, total, 7, -17, 0.3, 17.0)
    t += bed_layer("ice2", key_hz, total, -12, -19, 0.35, 31.0)
    if dark:
        t += bed_layer("dark", key_hz, total, -12, -15, 0.5, 9.0)
    # Motif: slices of the pentatonic drone, tuned to the scale, sparse.
    drone = load("drone")
    base = to_key(drone, key_hz)
    scale = [0, 2, 4, 7, 9, 12, 14]
    at = 2.0
    while at < total - 6:
        deg = scale[rng.integers(len(scale))] + register
        st = int(rng.integers(0, max(1, drone.shape[1] - 5 * SR)))
        seg = drone[:, st:st + int(rng.uniform(3.0, 5.0) * SR)]
        seg = stretch(seg, 0.6, base + deg)
        seg = seg * env(seg.shape[1], 1.6, 3.0)
        place(t, seg, at, motif_db + rng.uniform(-3, 0), rng.uniform(-0.7, 0.7))
        at += rng.uniform(*motif_gap)
    # Harp glints.
    harp = load("harp")
    hb = to_key(harp, key_hz)
    at = rng.uniform(6, 14)
    while at < total - 10:
        g = stretch(harp, 1.0, hb + [0, 7, 12][rng.integers(3)])
        place(t, g * env(g.shape[1], 0.05, 3.0), at, -22 + rng.uniform(-3, 0), rng.uniform(-0.5, 0.5))
        at += rng.uniform(*glint_gap)
    # Granular air.
    for src in ["air", "air2"]:
        a = load(src)
        at = rng.uniform(0, 10)
        while at < total - 8:
            place(t, stretch(a, 0.5, to_key(a, key_hz)) * env(int(16 * SR), 3, 4)[None, :] if False else stretch(a, 0.5, to_key(a, key_hz)), at, air_db, rng.uniform(-1, 1))
            at += rng.uniform(14, 26)
    # Slow, gentle compression keeps the bed even (ambient, not a dynamic piece).
    board = Pedalboard([HighpassFilter(40), LowpassFilter(6500),
        Compressor(threshold_db=-34, ratio=3.5, attack_ms=400, release_ms=2500), Gain(6),
        Reverb(room_size=0.92, damping=0.5, wet_level=0.42, dry_level=0.7, width=1.0)])
    t = board(t, SR)
    # Seamless loop: the 8 s tail fades into the head.
    n = int(length * SR)
    x = int(8.0 * SR)
    fade = np.linspace(0, 1, x, dtype=np.float32)
    head = t[:, :x] * fade + t[:, n:n + x] * (1 - fade)
    loop = np.concatenate([head, t[:, x:n]], axis=1)
    # Level: about -20 dBFS RMS, peaks under -3 dB.
    rms = np.sqrt(np.mean(loop ** 2)) + 1e-9
    loop *= 10 ** (-20 / 20.0) / rms
    pk = np.abs(loop).max()
    if pk > 0.7:
        loop *= 0.7 / pk
    write(loop, "music/" + name)


def sting(name, key_hz):
    total = 9.0
    t = np.zeros((2, int(total * SR)), np.float32)
    pad = load("pad")
    s = stretch(pad, 0.5, to_key(pad, key_hz))[:, :int(8 * SR)]
    place(t, s * env(s.shape[1], 0.4, 4.0), 0.0, -8, 0)
    harp = load("harp")
    for k, (deg, at) in enumerate([(0, 0.1), (7, 0.5), (12, 0.9)]):
        g = stretch(harp, 1.0, to_key(harp, key_hz) + deg)
        place(t, g * env(g.shape[1], 0.02, 3.0), at, -12, [-0.4, 0.0, 0.4][k])
    t = Pedalboard([HighpassFilter(60), Reverb(room_size=0.85, wet_level=0.4, dry_level=0.8)])(t, SR)
    t *= 0.6 / (np.abs(t).max() + 1e-9)
    write(t, "music/" + name)


def write(a, rel):
    os.makedirs(TMP, exist_ok=True)
    wav = os.path.join(TMP, rel.replace("/", "_") + ".wav")
    sf.write(wav, a.T, SR)
    out = os.path.normpath(os.path.join(OUT, rel + ".ogg"))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    print("wrote", out, "%.1f s" % (a.shape[1] / SR))


# Sound effects: name -> (source, start s, length s, gain dB)
SFX = {
    "ui_click": ("Rogue Waves - Kawaii UI/UIClick_Operating System UI Cursor_RogueWaves_KawaiiUI.wav", 0, 0.4, -8),
    "ui_open": ("Shapeforms Audio - Future UI/FUI Navigation Swipe-2.wav", 0, 1.2, -10),
    "ui_place": ("Shapeforms Audio - Future UI/FUI Ease Into Position.wav", 0, 1.2, -9),
    "ui_deny": ("Cinematic Sound Design - System & UI Feedback Elements/Interface Deny Low Fat Dark.wav", 0, 0.8, -10),
    "ui_confirm": ("Cinematic Sound Design - User Interface/Interface Plucks Happy.wav", 0, 1.5, -10),
    "gene_up": ("CB_Sounddesign - Applicable Sounds - Organic UI and Building Games SFX/UIMisc_Kalimba 3 Up_CB Sounddesign_APPlicable Sounds.wav", 0, 1.2, -10),
    "star": ("Scoba Sounds – Scoba Ui Essentials/BALAFON - NOTIF OCT UP.wav", 0, 1.5, -6),
    "success": ("Cinematic Sound Design - User Interface/Button Arp Twinkle.wav", 0, 2.5, -8),
    "fail": ("Cinematic Sound Design - System & UI Feedback Elements/Interface Sci-Fi Ping Down.wav", 0, 2.0, -10),
    "release": ("David Dumais Audio - Water Magic 1/Magic_Spells_CastLong_Water_General05.wav", 0, 3.5, -10),
    "nutrient": ("David Dumais Audio - Water Magic 1/Magic_Spells_CastShort_Water_General07.wav", 0, 1.8, -11),
    "cold": ("David Dumais Audio - Ice & Frost Magic 1/Magic_Spells_CastShort_Ice_General24.wav", 0, 2.0, -11),
    "warm": ("David Dumais Audio - Air Magic 1/Magic_Spells_Impact_Air24.wav", 0, 2.0, -11),
    "current": ("344 Audio - Elemental Palette Designed Vol. 1/WINDDsgn_Wind, Rush, Whoosh, Long x5 01_344 Audio_Elemental Palette Designed Vol 1.wav", 0, 2.2, -14),
    "bubble": ("344 Audio - Elemental Palette Designed Vol. 1/WATRMisc_Water, Liquid Impact, Bubble, Sci Fi, Hit 04_344 Audio_Elemental Palette Designed Vol 1.wav", 0, 1.0, -16),
    "engulf": ("InMotionAudio - Submerge/WATRImpt_Impact20_InMotionAudio_Submerge.wav", 0, 1.6, -15),
    "mutation": ("Shapeforms Audio - Future UI/FUI Hologram Ping Tone Echoed-2.wav", 0, 2.0, -14),
    "dive": ("Shapeforms Audio - Future UI/Short Rising Flutter.wav", 0, 1.8, -10),
    # The holographic interface (fourth round).
    "holo_boot": ("BluezoneCorp - Futuristic User Interface/Bluezone_BC0303_futuristic_user_interface_transition_006.wav", 0, 1.44, -9),
    "holo_on": ("BluezoneCorp - Futuristic User Interface/Bluezone_BC0303_futuristic_user_interface_data_glitch_003.wav", 0.7, 0.5, -14),
    "holo_banner": ("Membrans - Spaceship Interface Sound Pack 01/Spaceship Interface 33.wav", 0, 0.78, -10),
    "holo_tick": ("BluezoneCorp - Futuristic User Interface/Bluezone_BC0303_futuristic_user_interface_high_tech_beep_038.wav", 0, 0.08, -16),
}


def cut_sfx():
    for name, (src, start, length, gain) in SFX.items():
        with AudioFile(LIB + src).resampled_to(SR) as f:
            a = f.read(f.frames)
        if a.shape[0] == 1:
            a = np.vstack([a, a])
        a = a[:2, int(start * SR):int((start + length) * SR)].astype(np.float32)
        a = a * env(a.shape[1], 0.003, min(0.25, length * 0.3))[None, :]
        pk = np.abs(a).max() + 1e-9
        a = a / pk * 10 ** (gain / 20.0)
        write(a, "sfx/" + name)


if __name__ == "__main__":
    D = 146.83  # D3
    A = 110.0   # A2
    compose("menu", D, 150.0, (5.0, 9.0), -15, (18, 30), 12)
    compose("dish", D, 180.0, (7.0, 13.0), -17, (28, 45), 0)
    compose("lab", A, 150.0, (6.0, 11.0), -17, (30, 50), 12, dark=True)
    sting("result", D)
    cut_sfx()
