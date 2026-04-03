# utilites

## mp3_convert_64

### mp3_convert_64.zsh

* Перекодирует все `.mp3` в текущей папке
* Делает:

  * 64 kbps
  * mono
  * нормализацию звука
* Показывает прогресс

Запуск:
cd /папка/с/mp3
zsh mp3_convert_64.zsh

### mp3_convert_64_old.zsh

* Старая версия скрипта, fallback

---

## youtube_download-rename

### youtube_download_640.sh

* Скачивает YouTube (видео / плейлист / канал)
* Ограничение: ≤ 640p → MP4
* Не скачивает дубли (archive)
* Поддерживает cookies

Запуск:
bash youtube_download_640.sh

Опции:
--cookies-file path
--cookies-browser chrome|safari|firefox
--max N

---

### rename_from_csv.py

* Переименовывает файлы по CSV
* Берёт:

  * video — текущее имя файла
  * caption_ru — новое имя
* Делает:

  * ВСЕ БУКВЫ В ВЕРХНИЙ РЕГИСТР
  * убирает запрещённые символы

Запуск:
python rename_from_csv.py --dir ./videos --csv titles.csv
python rename_from_csv.py --dir ./videos --csv titles.csv --apply

---

### youtube_cookies.txt

* Cookies для yt-dlp (если нужен доступ к приватному/ограниченному)

---

## Быстрый пайплайн

bash youtube_download_640.sh
python rename_from_csv.py --dir ./YouTubeArchive --csv titles.csv --apply
cd ./mp3 && zsh mp3_convert_64.zsh

---

## Требования

* yt-dlp
* ffmpeg
* python3
