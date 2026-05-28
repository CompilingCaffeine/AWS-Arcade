# Upload Pipeline

## Valid Package Shape

```text
game.zip
├── index.html
├── manifest.json
├── app.js
├── styles.css
└── assets/
```

`manifest.json` must match the schema in `schemas/manifest.schema.json`.

## Pipeline Steps

1. Upload a ZIP file to the uploads bucket under `incoming/`.
2. S3 sends an ObjectCreated event to Lambda.
3. Lambda downloads the ZIP to `/tmp`.
4. Lambda validates:
   - file extension is `.zip`
   - archive size and file count are within limits
   - paths do not use `..` or absolute paths
   - `manifest.json` exists
   - manifest has required metadata
   - the configured entrypoint exists
5. Lambda deletes any existing deployed files under `games/{game_id}/`.
6. Lambda uploads the package contents to the site bucket.
7. Lambda writes or updates the DynamoDB catalog record.
8. Lambda regenerates `catalog/catalog.json`.
9. Lambda creates a CloudFront invalidation.

## Upload Command

```bash
aws s3 cp my-game.zip s3://<upload-bucket>/incoming/my-game.zip
```

## Public URLs

With custom domains enabled:

- Portfolio: `https://play.herzi.ai/`
- Game: `https://play.herzi.ai/games/{game_id}/`

Without custom domains:

- Portfolio: `https://<cloudfront-domain>/`
- Game: `https://<cloudfront-domain>/games/{game_id}/`

