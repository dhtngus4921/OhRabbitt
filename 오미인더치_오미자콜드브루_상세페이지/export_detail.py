from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
WORK = ROOT / "export_work"
RAW = WORK / "full_raw.png"
OUT = ROOT / "export"
FULL_NAME = "오미인더치_오미자콜드브루_상세페이지_전체.png"
SLICE_STEM = "오미자콜드브루"
MANIFEST_NAME = "export-manifest.json"
CONTACT_NAME = "검수표.jpg"

TARGET_HEIGHT = 3400
MIN_HEIGHT = 2600
MAX_HEIGHT = 4000
SEARCH_RADIUS = 650
JPEG_QUALITY = 90
MAX_JPEG_BYTES = 4_800_000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def trim_document(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.int16)
    background = np.array([236, 232, 226], dtype=np.int16)
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
    kernel = np.ones(31, dtype=np.float32) / 31
    score = np.convolve(row_std, kernel, mode="same") + np.convolve(row_edge, kernel, mode="same") * 9

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


def save_jpeg_under_limit(image: Image.Image, path: Path) -> tuple[int, int]:
    quality = JPEG_QUALITY
    while True:
        image.convert("RGB").save(path, "JPEG", quality=quality, optimize=True, progressive=True, subsampling=0)
        size = path.stat().st_size
        if size <= MAX_JPEG_BYTES or quality <= 78:
            return quality, size
        quality -= 3


def make_contact_sheet(paths: list[Path], destination: Path) -> None:
    thumb_width = 240
    margin = 24
    label_height = 34
    thumbs: list[Image.Image] = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        height = round(image.height * thumb_width / image.width)
        thumbs.append(image.resize((thumb_width, height), Image.Resampling.LANCZOS))
    sheet_height = margin + sum(image.height + label_height + margin for image in thumbs)
    sheet = Image.new("RGB", (thumb_width + margin * 2, sheet_height), "#eeeae4")
    draw = ImageDraw.Draw(sheet)
    y = margin
    for index, image in enumerate(thumbs, start=1):
        draw.text((margin, y), f"COUPANG {index:02d}", fill="#332824")
        y += label_height
        sheet.paste(image, (margin, y))
        y += image.height + margin
    sheet.save(destination, "JPEG", quality=86, optimize=True)


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
        segment = page.crop((0, top, page.width, bottom))
        path = OUT / f"쿠팡_{index:02d}_{SLICE_STEM}.jpg"
        quality, size = save_jpeg_under_limit(segment, path)
        slice_paths.append(path)
        manifest["slices"].append({"order": index, "file": path.name, "width": segment.width, "height": segment.height, "top": top, "bottom": bottom, "jpeg_quality": quality, "bytes": size, "sha256": sha256(path)})

    contact_path = OUT / CONTACT_NAME
    make_contact_sheet(slice_paths, contact_path)
    manifest["contact_sheet"] = contact_path.name
    manifest["contact_sheet_sha256"] = sha256(contact_path)
    (OUT / MANIFEST_NAME).write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
