import argparse, csv, os, re, sys, unicodedata
from pathlib import Path

def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s or "")

def sanitize(name: str, max_len: int = 200) -> str:
    name = nfc(name).replace("\n", " ").replace("\r", " ").strip()
    name = re.sub(r'[\\/:*?"<>|]', " ", name)  # недопустимые символы в имени файла
    name = re.sub(r"\s+", " ", name).strip(" .")
    return name[:max_len]

def sniff_delimiter(sample: str) -> str:
    cand = [';', ',', '\t', '|']
    counts = {d: sample.count(d) for d in cand}
    return max(counts, key=counts.get) if any(counts.values()) else ','

def read_rows(csv_path: Path):
    with open(csv_path, 'r', encoding='utf-8-sig', newline='') as f:
        head = f.read(4096)
        f.seek(0)
        delim = sniff_delimiter(head)
        reader = csv.DictReader(f, delimiter=delim)
        if not reader.fieldnames:
            raise ValueError("Не удалось распознать заголовки CSV.")
        fieldnames = [nfc(h).strip() for h in reader.fieldnames]
        rows = []
        for row in reader:
            norm = {}
            for k, v in row.items():
                nk = nfc(k).strip()
                norm[nk] = nfc((v or "").strip())
            rows.append(norm)
        return fieldnames, rows, delim

def main():
    ap = argparse.ArgumentParser(description="Переименование файлов по CSV (video -> caption_ru, CAPS)")
    ap.add_argument("--dir", required=True, help="Папка с видео для переименования")
    ap.add_argument("--csv", required=True, help="Путь к vk_titles.csv")
    ap.add_argument("--apply", action="store_true", help="Внести изменения (без флага — только показ)")
    args = ap.parse_args()

    target_dir = Path(args.dir)
    if not target_dir.is_dir():
        print("Папка не найдена:", target_dir); sys.exit(1)

    files = [p for p in target_dir.iterdir() if p.is_file()]
    by_name = {nfc(p.name): p for p in files}

    try:
        fieldnames, rows, delim = read_rows(Path(args.csv))
    except Exception as e:
        print("Ошибка чтения CSV:", e); sys.exit(1)

    if "video" not in fieldnames or "caption_ru" not in fieldnames:
        print(f"В CSV должны быть колонки: 'video' и 'caption_ru'. Найдены: {fieldnames}")
        print(f"(Определённый разделитель: '{delim}')")
        sys.exit(1)

    actions, missing = [], []

    for i, row in enumerate(rows, 1):
        old_name = nfc((row.get("video") or "").strip())
        new_base = nfc((row.get("caption_ru") or "").strip())
        if not old_name or not new_base:
            print(f"[{i}] Пропуск: пустые video/caption_ru"); continue

        src = by_name.get(old_name)
        if src is None:
            base = Path(old_name).stem
            candidates = [p for p in files if nfc(p.stem) == base]
            if len(candidates) == 1:
                src = candidates[0]

        if src is None:
            missing.append(old_name); continue

        safe_new = sanitize(new_base).upper()   # <<<<<<<<<< капс
        if not safe_new:
            print(f"[{i}] Пропуск: пустое имя для '{old_name}'"); continue

        dst = src.with_name(f"{safe_new}{src.suffix.lower()}")
        n = 2
        while dst.exists() and dst != src:
            dst = src.with_name(f"{safe_new}_{n}{src.suffix.lower()}")
            n += 1

        if src != dst:
            actions.append((src, dst))

    print("\nНайдено к переименованию:", len(actions))
    for src, dst in actions:
        print(f"{src.name}  →  {dst.name}")

    if missing:
        print("\nНе найдены в папке:")
        for name in missing:
            print(" -", name)

    if not args.apply:
        print("\nDRY-RUN: изменений не выполнял. Добавь --apply для применения.")
        return

    for src, dst in actions:
        try: src.rename(dst)
        except Exception as e:
            print(f"Ошибка '{src.name}' → '{dst.name}': {e}")

    print("\nГотово.")

if __name__ == "__main__":
    main()
