#!/usr/bin/env python3
import json
import os
import sys


def _load_pillow():
    try:
        from PIL import Image
        return Image
    except Exception:
        return None


def _average(values):
    return sum(values) / len(values) if values else 0.0


def _visual_tags_for_image(image_path):
    Image = _load_pillow()
    if Image is None:
        return ''

    if not image_path or not os.path.exists(image_path):
        return ''

    try:
        with Image.open(image_path) as img:
            img = img.convert('RGB')
            img = img.resize((96, 96))
            pixels = list(img.getdata())
    except Exception:
        return ''

    if not pixels:
        return ''

    brightness_values = []
    saturation_values = []
    warm = 0
    cool = 0
    greenish = 0
    blueish = 0
    skin_like = 0
    colorful = 0

    for r, g, b in pixels:
        rf = r / 255.0
        gf = g / 255.0
        bf = b / 255.0

        maxv = max(rf, gf, bf)
        minv = min(rf, gf, bf)
        delta = maxv - minv
        brightness = (rf + gf + bf) / 3.0
        saturation = 0.0 if maxv == 0 else delta / maxv

        brightness_values.append(brightness)
        saturation_values.append(saturation)

        if rf > bf and rf >= gf:
            warm += 1
        if bf > rf and bf >= gf:
            cool += 1
        if gf > rf * 1.06 and gf > bf * 1.06:
            greenish += 1
        if bf > rf * 1.08 and bf > gf * 0.95:
            blueish += 1
        if r > 95 and g > 40 and b > 20 and (max(r, g, b) - min(r, g, b)) > 15 and abs(r - g) > 15 and r > g and r > b:
            skin_like += 1
        if saturation > 0.55:
            colorful += 1

    total = float(len(pixels))
    avg_brightness = _average(brightness_values)
    avg_saturation = _average(saturation_values)
    warm_ratio = warm / total
    cool_ratio = cool / total
    green_ratio = greenish / total
    blue_ratio = blueish / total
    skin_ratio = skin_like / total
    colorful_ratio = colorful / total

    tags = []

    if avg_brightness < 0.30:
        tags.extend(['dark', 'dim'])
    elif avg_brightness > 0.72:
        tags.extend(['bright', 'well lit'])

    if avg_saturation < 0.18:
        tags.extend(['muted', 'low saturation'])
    elif avg_saturation > 0.52:
        tags.extend(['vivid', 'colorful'])

    if warm_ratio > 0.48:
        tags.extend(['warm', 'indoor'])
    elif cool_ratio > 0.48:
        tags.extend(['cool tone'])

    if green_ratio > 0.24:
        tags.extend(['outdoor', 'nature', 'green scene'])

    if blue_ratio > 0.22:
        tags.extend(['blue scene', 'sky', 'pool', 'outdoor'])

    if skin_ratio > 0.18:
        tags.extend(['skin', 'portrait', 'close up'])
    elif skin_ratio > 0.10:
        tags.extend(['person'])

    if colorful_ratio > 0.30:
        tags.extend(['vibrant'])

    # dedupe preserving order
    deduped = []
    seen = set()
    for tag in tags:
        if tag in seen:
            continue
        deduped.append(tag)
        seen.add(tag)

    return ' '.join(deduped)


def _cmd_extract_visual_tags(input_path, output_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        payload = json.load(f)

    image_paths = payload.get('image_paths', [])
    result = {}
    for image_path in image_paths:
        result[image_path] = _visual_tags_for_image(image_path)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump({'result': result}, f)


def main():
    if len(sys.argv) < 4:
        print('Usage: semantic_worker.py extract-visual-tags input.json output.json', file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    input_path = sys.argv[2]
    output_path = sys.argv[3]

    if cmd == 'extract-visual-tags':
        _cmd_extract_visual_tags(input_path, output_path)
        return

    print(f'Unknown command: {cmd}', file=sys.stderr)
    sys.exit(1)


if __name__ == '__main__':
    main()
