---
name: upload-notion-image
description: Upload local images to Notion pages natively via the Notion API file upload flow. No external hosting needed — images live inside Notion. Use when embedding images in Notion pages.
tags: [personal]
---

## What This Skill Does

Uploads local image files directly to Notion using their file upload API, then attaches them as image blocks on a page. Images are hosted by Notion itself — no external hosting (imgur, catbox, GitHub) needed.

## Prerequisites

- `NOTION_API_KEY` — a Notion integration token, stored in 1Password and fetched at runtime via `secret NOTION_API_KEY` (never hardcoded or written to a shell profile)
- The integration must have access to the target page/database (shared via Notion's "Connect to" menu)
- `curl` and `python3` available in the shell

### One-Time Setup

If `secret NOTION_API_KEY` returns nothing:

1. Go to [https://www.notion.so/my-integrations](https://www.notion.so/my-integrations)
2. Create a new integration (name it anything, e.g. "Claude Code")
3. Copy the "Internal Integration Secret" (a Notion integration token)
4. Store it in 1Password as the `NOTION_API_KEY` field of the `shell-env` item (vault `claude`), so `secret NOTION_API_KEY` returns it — never paste it into a shell profile or any file
5. In Notion, open the target database/page → click `...` → "Connect to" → select your integration

Recipes below read `$NOTION_API_KEY`; populate it for the session with `export NOTION_API_KEY="$(secret NOTION_API_KEY)"`.

## Usage

### Via the bash script

The skill includes `upload.sh` which handles the full 3-step flow:

```bash
# Append an image to the end of a page
./upload.sh <image_path> <page_id> [caption]

# Insert an image after a specific block (for interleaving with text)
./upload.sh <image_path> <page_id> [caption] --after <block_id>

# Examples
./upload.sh hero.png abc123 "A robot writing in a journal"
./upload.sh hero.png abc123 "A robot writing" --after def456
```

The `--after` flag inserts the image after a specific block instead of appending to the end. Get block IDs by listing page children:

```bash
curl -s "https://api.notion.com/v1/blocks/$PAGE_ID/children?page_size=100" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2025-09-03" | python3 -c "
import sys, json
for b in json.load(sys.stdin)['results']:
    t = b['type']
    rid = b['id']
    text = ''
    if t in ('heading_2','heading_3','paragraph') and b[t].get('rich_text'):
        text = b[t]['rich_text'][0]['plain_text'][:60]
    print(f'{rid}  {t}: {text}')
"
```

The script prints the `file_upload_id` on success, which can be reused for covers/icons.

### Batch upload (multiple images to one page)

```bash
SKILL_DIR=".claude/skills/upload-notion-image"
PAGE_ID="your-page-id-here"

for img in working/2026-03-22/*.png; do
  bash "$SKILL_DIR/upload.sh" "$img" "$PAGE_ID" "$(basename "$img" .png)"
done
```

### Setting a page cover or icon

The script appends images as blocks. For covers/icons, use the `file_upload_id` from the script output with a manual curl call:

```bash
# Set as page cover
curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2025-09-03" \
  -H "Content-Type: application/json" \
  -d "{\"cover\":{\"type\":\"file_upload\",\"file_upload\":{\"id\":\"$FILE_UPLOAD_ID\"}}}"

# Set as page icon
curl -s -X PATCH "https://api.notion.com/v1/pages/$PAGE_ID" \
  -H "Authorization: Bearer $NOTION_API_KEY" \
  -H "Notion-Version: 2025-09-03" \
  -H "Content-Type: application/json" \
  -d "{\"icon\":{\"type\":\"file_upload\",\"file_upload\":{\"id\":\"$FILE_UPLOAD_ID\"}}}"
```

## How It Works

The Notion file upload API is a 3-step process:

1. **Create a file upload object** — `POST /v1/file_uploads` with filename and content type. Returns an `upload_url` and `id`.
2. **Upload the binary** — `POST` the file to the `upload_url` as multipart/form-data. Status changes to `"uploaded"`.
3. **Attach to a page** — Use the `id` in an image block, cover, or icon via the blocks or pages API.

Uploaded files must be attached within **1 hour** or they expire. Once attached, they're permanent and hosted by Notion.

## Limitations

- **Free workspaces:** 5 MB per file
- **Paid workspaces:** 5 GB per file (use multi-part upload for files > 20 MB)
- **Supported image types:** .png, .jpg, .jpeg, .gif, .webp, .svg, .heic
- **The Notion MCP doesn't support `file_upload` type** — this skill bypasses the MCP and calls the API directly via curl. The MCP's `notion-create-pages` and `notion-update-page` tools only accept external URLs for images.

## Integration with Other Skills

Skills that generate images for Notion should use this skill instead of external hosting:

```bash
# Instead of uploading to catbox.moe and using external URLs:
SKILL_DIR=".claude/skills/upload-notion-image"
bash "$SKILL_DIR/upload.sh" "$IMAGE_PATH" "$PAGE_ID" "$CAPTION"
```
