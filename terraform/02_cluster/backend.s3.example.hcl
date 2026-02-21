# Configuration backend S3 + DynamoDB pour 02_cluster (lié à ton compte AWS).
# Copier en backend.s3.hcl, remplacer le bucket et la region, ne pas committer backend.s3.hcl.
#
# 1) Créer le bucket S3 et la table DynamoDB (verrouillage du state) :
#
#   export AWS_REGION=eu-west-1
#   export BUCKET=my-infomaniak-k8s-tf-state
#
#   aws s3api create-bucket --bucket $BUCKET --region $AWS_REGION
#   aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
#   aws s3api put-bucket-encryption --bucket $BUCKET --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   aws dynamodb create-table \
#     --table-name terraform-state-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region $AWS_REGION
#
# 2) Renseigner les paramètres ci-dessous et lancer :
#
#   terraform init -reconfigure -backend-config=backend.s3.hcl
#
# 3) Credentials AWS : AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY et AWS_REGION (ou ~/.aws/credentials).

bucket         = "MON_BUCKET_TERRAFORM_STATE"
key            = "02_cluster/terraform.tfstate"
region         = "eu-west-1"
dynamodb_table = "terraform-state-lock"
encrypt        = true
