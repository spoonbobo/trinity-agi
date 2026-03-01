---
name: doc-convert
description: Convert and extract text from PDFs, DOCX, images (OCR), and other document formats using the gateway's built-in document processing stack.
homepage: https://github.com/trinityagi/trinity-agi
metadata:
  {
    "openclaw":
      {
        "emoji": "📑",
        "requires": { "bins": ["pdftotext", "pandoc", "tesseract"] },
      },
  }
---

# doc-convert

Extract text from PDFs, DOCX files, images (via OCR), and other document formats.
All tools are pre-installed in the OpenClaw gateway container.

## Available Tools

| Tool | Binary | Purpose |
|------|--------|---------|
| pdftotext | `pdftotext` (poppler-utils) | Extract text from PDF files |
| pdfinfo | `pdfinfo` (poppler-utils) | Get PDF metadata (page count, size, etc.) |
| pdfimages | `pdfimages` (poppler-utils) | Extract images from PDFs |
| pandoc | `pandoc` | Convert between formats (DOCX->text, HTML->md, etc.) |
| tesseract | `tesseract` | OCR - extract text from images |
| python3 | `python3` | pdfplumber, PyPDF2, python-docx, Pillow, pytesseract |
| libreoffice | `libreoffice` | Convert DOCX/XLSX/PPTX to PDF |
| imagemagick | `convert` / `identify` | Image manipulation and format conversion |

## Quick Reference

### PDF to text
```bash
pdftotext input.pdf -                    # stdout
pdftotext -layout input.pdf output.txt   # preserve layout
pdftotext -f 1 -l 5 input.pdf -         # pages 1-5 only
```

### PDF metadata
```bash
pdfinfo input.pdf
```

### DOCX to plain text
```bash
pandoc -f docx -t plain input.docx       # stdout
pandoc -f docx -t markdown input.docx    # as markdown
```

### DOCX to PDF
```bash
libreoffice --headless --convert-to pdf input.docx
```

### Image OCR
```bash
tesseract image.png stdout               # extract text from image
tesseract image.png output -l eng pdf    # OCR to searchable PDF
tesseract image.png stdout -l chi_sim    # Chinese OCR
```

### HTML to Markdown
```bash
pandoc -f html -t markdown input.html
```

### Python (advanced extraction)
```python
# PDF with tables
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    for page in pdf.pages:
        print(page.extract_text())
        for table in page.extract_tables():
            print(table)

# DOCX
from docx import Document
doc = Document("file.docx")
for para in doc.paragraphs:
    print(para.text)

# Image OCR via Python
from PIL import Image
import pytesseract
text = pytesseract.image_to_string(Image.open("image.png"))
print(text)
```

## Supported Formats

| Format | Read | Convert To |
|--------|------|-----------|
| PDF | pdftotext, pdfplumber, PyPDF2 | text, markdown, images |
| DOCX | pandoc, python-docx | text, markdown, PDF |
| HTML | pandoc | text, markdown, PDF |
| Images (PNG/JPG/TIFF/BMP) | tesseract (OCR) | text, searchable PDF |
| XLSX/PPTX | libreoffice | PDF, then text |
| RTF | pandoc | text, markdown |
| EPUB | pandoc | text, markdown |
| ODT | pandoc, libreoffice | text, PDF |

## Notes

- For scanned PDFs (images, not text), use `tesseract` or `pdfplumber` with image extraction.
- `pdftotext` is fastest for text-based PDFs. Use `pdfplumber` when you need table extraction.
- `pandoc` handles format conversion between most document types.
- Large files: use page ranges (`pdftotext -f 1 -l 10`) to avoid memory issues.
- OCR quality depends on image resolution; 300 DPI recommended.
