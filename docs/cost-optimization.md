# Cost Optimization

- Use S3 and CloudFront for static hosting instead of servers.
- Use Lambda only when uploads occur.
- Use DynamoDB `PAY_PER_REQUEST` for small or spiky catalog traffic.
- Keep CloudFront `PriceClass_100` for a lower-cost MVP.
- Cache static game files at CloudFront and only invalidate changed paths.
- Keep `catalog/catalog.json` small and cached briefly.
- Add lifecycle expiration on uploaded ZIP files.
- Avoid broad `/*` invalidations; they can become expensive after the free monthly invalidation allowance.
- Keep Lambda memory modest, then tune using CloudWatch duration metrics.
- Do not enable optional high-volume logs until needed.
- Prefer compression at CloudFront for text assets.

