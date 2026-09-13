from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
WORK = ROOT / "export_work"
RAW = WORK / "full_raw.png"
OUT = ROOT / "export"
FULL_NAME = "오토끼_우리쌀라이스칩_상세페이지_전체.png"
SLICE_PREFIX = "오토끼_우리쌀라이스칩_상세"

TARGET_HEIGHT = 3400
MIN_HEIGHT = 2500
MAX_HEIGHT = 4100
SEARCH_RADIUS = 650
JPEG_QUALITY = 90
MAX_JPEG_BYTES = 4_800_000


def trim_document(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    background = np.array([232, 229, 223], dtype=np.int16)
    distance = np.max(np.abs(rgb - background), axis=2)
    active_fraction = (distance > 5).mean(axis=1)
    active_rows = np.flatnonzero(active_fraction > 0.02)
    if not len(active_rows):
        raise RuntimeError("상세페이지 영역을 찾지 못했습니다.")
    bottom = min(image.height, int(active_rows[-1]) + 1)
    return image.crop((0, 0, image.width, bottom))


def choose_cuts(image: Image.Image) -> list[int]:
    small = image.convert("RGB").resize((215, image.height), Image.Resampling.BILINEAR)
    arr = np.asarray(small, dtype=np.float32)
    row_std = arr.std(axis=(1, 2))
    row_edge = np.zeros(image.height, dtype=np.float32)
    row_edge[1:] = np.abs(arr[1:] - arr[:-1]).mean(axis=(1, 2))

    kernel = np.ones(25, dtype=np.float32) / 25
    smooth_std = np.convolve(row_std, kernel, mode="same")
    smooth_edge = np.convolve(row_edge, kernel, mode="same")
    score = smooth_std + smooth_edge * 8

    cuts: list[int] = []
    start = 0
    while image.height - start > MAX_HEIGHT:
        target = start + TARGET_HEIGHT
        low = max(start + MIN_HEIGHT, target - SEARCH_RADIUS)
        high = min(start + MAX_HEIGHT, target + SEARCH_RADIUS, image.height - MIN_HEIGHT)
        if high <= low:
            cut = min(start + MAX_HEIGHT, image.height)
        else:
            cut = int(low + np.argmin(score[low:high]))
        cuts.append(cut)
        start = cut
    return cuts


def save_jpeg_under_limit(image: Image.Image, path: Path) -> tuple[int, int]:
    quality = JPEG_QUALITY
    while True:
        image.convert("RGB").save(
            path,
            "JPEG",
            quality=quality,
            optimize=True,
            progressive=True,
            subsampling=0,
            dpi=(72, 72),
        )
        size = path.stat().st_size
        if size <= MAX_JPEG_BYTES or quality <= 78:
            return quality, size
        quality -= 3


def main() -> None:
    if not RAW.exists():
        raise FileNotFoundError(f"렌더링 원본이 없습니다: {RAW}")

    OUT.mkdir(parents=True, exist_ok=True)
    image = Image.open(RAW)
    image.load()
    page = trim_document(image)
    if page.width != 860:
        raise RuntimeError(f"렌더링 폭이 860px이 아닙니다: {page.width}px")

    full_path = OUT / FULL_NAME
    page.save(full_path, "PNG", optimize=True, dpi=(72, 72))

    cuts = choose_cuts(page)
    boundaries = [0, *cuts, page.height]
    manifest = {
        "canvas_width": page.width,
        "full_height": page.height,
        "full_file": full_path.name,
        "slices": [],
    }

    for index, (top, bottom) in enumerate(zip(boundaries, boundaries[1:]), start=1):
        segment = page.crop((0, top, page.width, bottom))
        path = OUT / f"{SLICE_PREFIX}_{index:02d}.jpg"
        quality, size = save_jpeg_under_limit(segment, path)
        manifest["slices"].append(
            {
                "order": index,
                "file": path.name,
                "width": segment.width,
                "height": segment.height,
                "top": top,
                "bottom": bottom,
                "jpeg_quality": quality,
                "bytes": size,
            }
        )

    manifest_path = OUT / "오토끼_우리쌀라이스칩_상세페이지_EXPORT_MANIFEST.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
