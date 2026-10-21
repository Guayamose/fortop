# Derive independent, stable encryption material from Rails' secret. Explicit
# encryption keys can be supplied when separating secrets during deployment.
Rails.application.config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
  Rails.application.key_generator.generate_key("fortop/github_token/primary", 32).unpack1("H*")
Rails.application.config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
  Rails.application.key_generator.generate_key("fortop/github_token/deterministic", 32).unpack1("H*")
Rails.application.config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
  Rails.application.key_generator.generate_key("fortop/github_token/salt", 32).unpack1("H*")
