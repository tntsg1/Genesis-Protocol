"""Bring the user's Suno tracks into the game (2026-10-29, the biotech score).

Each background track: decoded at 48 kHz, leading and trailing silence cut,
then made to loop without a seam (its last XF seconds crossfaded over its
head, the result cut XF short so the end runs straight into the start), and
levelled to the game's loudness (background -22 LUFS, the result sting
-18 LUFS). The sting is cut, given a short fade-out and does not loop.
The tracks it replaces are copied to G: first.

Run: G:/audio_library/venv/Scripts/python.exe tools/import_suno_music.py
"""
import os
import shutil
import subprocess
import numpy as np
import soundfile as sf

FFMPEG = "C:/ProgramData/chocolatey/bin/ffmpeg"
DL = "C:/Users/tntsg/Downloads/"
WORK = "G:/audio_library/work/genesis_suno"
BACKUP = "G:/audio_library/work/genesis_music_backup_cc0"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "music")
SR = 48000
XF = 6.0

TRACKS = {
	"menu": ("sterile white laboratory.mp3", True, -22.0),
	"dish": ("Biotech Observation.mp3", True, -22.0),
	"lab": ("Biotech Observation (1).mp3", True, -22.0),
	"result": ("Success Alert.mp3", False, -18.0),
}


def run(*args):
	subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def trim(a, floor_db=-50.0):
	level = np.max(np.abs(a), axis=1)
	on = np.where(level > 10 ** (floor_db / 20.0))[0]
	return a[on[0]:on[-1] + 1] if on.size else a


def loop(a):
	n = int(XF * SR)
	head = a[:n]
	tail = a[-n:]
	t = np.linspace(0.0, 1.0, n)[:, None]
	# Equal-power crossfade: the tail fades out as the head fades in.
	mixed = tail * np.cos(t * np.pi / 2) + head * np.sin(t * np.pi / 2)
	out = a[:-n].copy()
	out[:n] = mixed
	return out


def main():
	os.makedirs(WORK, exist_ok=True)
	os.makedirs(BACKUP, exist_ok=True)
	for name, (src, loops, lufs) in TRACKS.items():
		cur = os.path.join(OUT, name + ".ogg")
		keep = os.path.join(BACKUP, name + ".ogg")
		if os.path.exists(cur) and not os.path.exists(keep):
			shutil.copy2(cur, keep)
		raw = os.path.join(WORK, name + "_raw.wav")
		run("-i", DL + src, "-ar", str(SR), "-ac", "2", raw)
		a, _ = sf.read(raw, dtype="float32")
		a = trim(a)
		if loops:
			a = loop(a)
		else:
			n = int(0.6 * SR)
			a[-n:] *= np.linspace(1.0, 0.0, n)[:, None]
		mid = os.path.join(WORK, name + "_cut.wav")
		sf.write(mid, a, SR)
		# Two-pass loudness: measure, then apply linearly (no dynamics change).
		probe = subprocess.run([FFMPEG, "-hide_banner", "-i", mid, "-af", "ebur128", "-f", "null", "-"],
			capture_output=True, text=True).stderr
		i = float(probe.split("Integrated loudness:")[1].split("I:")[1].split("LUFS")[0])
		gain = lufs - i
		run("-i", mid, "-af", "volume=%.2fdB,alimiter=limit=0.95:level=disabled" % gain,
			"-c:a", "libvorbis", "-q:a", "5", cur)
		print("%-6s %6.1f s  %+5.1f dB  (%s)" % (name, len(a) / SR, gain, src))


if __name__ == "__main__":
	main()
