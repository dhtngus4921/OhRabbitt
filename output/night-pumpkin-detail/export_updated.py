from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "export_work" / "full_raw.png"
OUT = ROOT / "certificate-updated-delivery"
FULL_NAME = "오토끼마켓_유기농밤호박_상세페이지_전체.png"
SLICE_PREFIX = "쿠팡"

TARGET_HEIGHT = 3000
MIN_HEIGHT = 2400
MAX_HEIGHT = 3600
SEARCH_RADIUS = 500
JPEG_QUALITY = 92
MAX_JPEG_BYTES = 4_800_000


def trim_document(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    background = np.array([231, 228, 220], dtype=np.int16)
    distance = np.max(np.abs(rgb - background), axis=2)
    active_fraction = (distance > 6).mean(axis=1)
    active_rows = np.flatnonzero(active_fraction > 0.02)
    if not len(active_rows):
        raise RuntimeError("상세페이지 영역을 찾지 못했습니다.")
    return image.crop((0, 0, image.width, int(active_rows[-1]) + 1))


def choose_cuts(image: Image.Image) -> list[int]:
    small = image.convert("RGB").resize((215, image.height), Image.Resampling.BILINEAR)
    arr = np.asarray(small, dtype=np.float32)
    row_std = arr.std(axis=(1, 2))
    row_edge = np.zeros(image.height, dtype=np.float32)
    row_edge[1:] = np.abs(arr[1:] - arr[:-1]).mean(axis=(1, 2))
    kernel = np.ones(25, dtype=np.float32) / 25
    score = np.convolve(row_std, kernel, mode="same") + np.convolve(row_edge, kernel, mode="same") * 8

    cuts: list[int] = []
    start = 0
    while image.height - start > MAX_HEIGHT:
        target = start + TARGET_HEIGHT
        low = max(start + MIN_HEIGHT, target - SEARCH_RADIUS)
        high = min(start + MAX_HEIGHT, target + SEARCH_RADIUS, image.height - MIN_HEIGHT)
        cut = min(start + MAX_HEIGHT, image.height) if high <= low else int(low + np.argmin(score[low:high]))
        cuts.append(cut)
        start = cut
    return cuts


def save_jpeg(image: Image.Image, path: Path) -> tuple[int, int]:
    quality = JPEG_QUALITY
    while True:
        image.convert("RGB").save(path, "JPEG", quality=quality, optimize=True, progressive=True, subsampling=0)
        size = path.stat().st_size
        if size <= MAX_JPEG_BYTES or quality <= 80:
            return quality, size
        quality -= 3


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_contact_sheet(paths: list[Path]) -> None:
    thumb_width = 300
    gap = 20
    thumbs = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        height = round(image.height * thumb_width / image.width)
        thumbs.append(image.resize((thumb_width, height), Image.Resampling.LANCZOS))
    columns = 2
    rows = (len(thumbs) + columns - 1) // columns
    row_heights = [max((thumbs[i].height for i in range(row * columns, min((row + 1) * columns, len(thumbs)))), default=0) for row in range(rows)]
    canvas = Image.new("RGB", (gap + columns * (thumb_width + gap), gap * (rows + 1) + sum(row_heights)), "white")
    draw = ImageDraw.Draw(canvas)
    y = gap
    for row in range(rows):
        x = gap
        for index in range(row * columns, min((row + 1) * columns, len(thumbs))):
            canvas.paste(thumbs[index], (x, y))
            draw.text((x + 8, y + 8), f"{index + 1:02d}", fill="black", stroke_width=2, stroke_fill="white")
            x += thumb_width + gap
        y += row_heights[row] + gap
    canvas.save(OUT / "검수표.png", "PNG", optimize=True)


def main() -> None:
    if not RAW.exists():
        raise FileNotFoundError(f"렌더링 원본이 없습니다: {RAW}")
    OUT.mkdir(parents=True, exist_ok=True)
    page = trim_document(Image.open(RAW))
    if page.width != 860:
        raise RuntimeError(f"렌더링 폭이 860px이 아닙니다: {page.width}px")

    full_path = OUT / FULL_NAME
    page.save(full_path, "PNG", optimize=True)
    boundaries = [0, *choose_cuts(page), page.height]
    manifest = {"canvas_width": page.width, "full_height": page.height, "full_file": full_path.name, "full_sha256": sha256(full_path), "slices": []}
    slice_paths: list[Path] = []
    for index, (top, bottom) in enumerate(zip(boundaries, boundaries[1:]), start=1):
        path = OUT / f"{SLICE_PREFIX}_{index:02d}_유기농밤호박.jpg"
        quality, size = save_jpeg(page.crop((0, top, page.width, bottom)), path)
        slice_paths.append(path)
        manifest["slices"].append({"order": index, "file": path.name, "width": 860, "height": bottom - top, "top": top, "bottom": bottom, "jpeg_quality": quality, "bytes": size, "sha256": sha256(path)})

    make_contact_sheet(slice_paths)
    (OUT / "export-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
