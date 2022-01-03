# jq (json query tool) | Development notes

## Filter

* Use case: Filter AWS IAM role ARN based on it's name:

> RoleName="lambda-aws-resource-tagger"

```bash
aws iam list-roles \
  | jq -c '.Roles[] | select( .RoleName | contains("lambda-aws-resource-tagger"))' |jq .Arn
```

### select

select (.type=="InternalIP")

## References

- [Manual](https://stedolan.github.io/jq/manual/)
