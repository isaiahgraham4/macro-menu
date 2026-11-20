# Leanrrr promo video (18 Nov 2026)

Two cuts of one 29.7 second advert, same scenes and copy:

- `Leanrrr-promo-youtube-1920x1080.mp4` (16:9, YouTube)
- `Leanrrr-promo-reels-tiktok-1080x1920.mp4` (9:16, Instagram Reels and TikTok)

Both are H.264, 30 fps, AAC stereo at about -14 LUFS.

## What is in it

- App footage: one screen recording of the Debug build on the iPhone 18 Pro Max simulator (`src/take1.mov`), sample data ending 18 Nov 2026, status bar 9:41, launched with `-LeanrForcePremium`. Nothing on the phone screen is drawn or edited; the phone frame, the enlarged cards (live crops of the same footage) and the grey tap marks are added by `promo.py`.
- Opening b-roll: two Gemini videos (Create video in the Gemini app, Pro plan), one landscape and one portrait, same prompt: a plain paper bag, a wrapped burger and a paper cup sliding onto a cream tabletop, no logos or text (`src/hook-land.mp4`, `src/hook-port.mp4`). Sped up 1.7x and 2x.
- Music: Gemini Create music, prompt "Smooth instrumental R&B for a short advert. Warm electric piano, deep bass, laid-back drums, finger snaps. Confident and feel-good." (`src/music-rnb.mp3`, 1:59; the video uses 5.6 s to 35.3 s so the drums come in as the phone appears at 3.3 s). The first track, upbeat funk pop, was rejected by Isaiah on 18 Nov 2026 and is kept as `src/music-funk-rejected.mp3`. Neither was listened to by a person before delivery.
- Type: Bebas Neue and Roboto from `Shared/Fonts`. Background is the app's order-pad cream with dots.

## Scenes and source times in take1.mov

| Scene | Copy | Source |
| --- | --- | --- |
| Hook | Eat out. Stay on target. | Gemini clip |
| Today | Calories left, at a glance. | 6.5 s |
| Find | Orders that fit what's left. | 34.5 s, 43.0 s |
| Food detail | The restaurant's own numbers. 31 restaurant chains (recounted 18 Nov 2026: 33 chain ids across the five menus, less Coles and Woolworths). | 121.6 s |
| Remove ingredients | Hold the cheese. See the change. | 131.7 s, 145.9 s, 148.6 s |
| Log | Log it in one tap. | 159.4 s, 170.7 s |
| Progress | See the trend. | 181.0 s |
| End card | Leanrrr. The calorie tracker for takeaway. No account. No sign-up. | drawn |

## Rebuild

ffmpeg is not installed on this Mac; `uv run --with imageio-ffmpeg python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())"` prints a usable binary.

1. Cut frames (30 fps JPEG, full size) into `<frames>/<name>/` with `ffmpeg -i src/take1.mov -ss <start> -t <length> -vf fps=30 -q:v 2 <name>/%04d.jpg` for: today 6.5/3.4, find1 34.5/3.6, find2 43.0/2.2, detail1 121.6/2.0, detail2 131.7/2.3, tog1 145.9/1.5, tog2 148.6/1.8, log1 159.4/2.0, log2 170.7/2.8, prog 181.0/2.4. Hook frames: `-ss 0.9 -t 5.7 -i src/hook-land.mp4 -vf setpts=PTS/1.7,fps=30` into `hookL`, `-ss 0.9 -t 6.7 -i src/hook-port.mp4 -vf setpts=PTS/2.0,fps=30` into `hookP`.
2. `SEG=<frames> FF=<ffmpeg> uv run --with pillow python promo.py L silent-L.mp4` (and `P`). Add `preview 0,300` style frame numbers as a third argument to write PNGs instead.
3. Mix the music (from 5.6 s, 2 s fade out) and the clip's own sound for the first 3.2 s, then `loudnorm=I=-14`.

Copy, scene lengths, crops and tap marks are all in the `SCENES` list at the top of `promo.py`.
