# Changelog

## Unreleased

- Sign the `x-amz-content-sha256` header in AWS Signature Version 4: it is now part of the canonical headers and of `SignedHeaders`. S3-compatible storages that require it to be signed (such as Huawei OceanStor) rejected requests before.

## 1.0.0 (4 19, 2023)

- Initial release of the `nginx-aws-signature` repository.
- Compatible with [`nginx-s3-gateway`](https://github.com/nginxinc/nginx-s3-gateway) and [`nginx-lambda-gateway`](https://github.com/nginx-serverless/nginx-lambda-gateway).
