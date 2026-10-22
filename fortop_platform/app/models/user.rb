class User < ApplicationRecord
  # Verified against GitHub's authenticated /user endpoint. A handle or email
  # must never grant administration, and the production database ID may differ.
  OWNER_GITHUB_ID = 63_518_682

  encrypts :github_token
  encrypts :github_refresh_token

  has_many :repositories, dependent: :destroy
  has_many :brands, dependent: :destroy
  has_many :brand_imports, dependent: :destroy
  has_many :brand_documents, through: :brand_imports, source: :documents

  validates :github_id, presence: true, uniqueness: true
  validates :login, :github_token, presence: true

  def self.from_github(profile, token:, refresh_token: nil, expires_at: nil)
    user = find_or_initialize_by(github_id: profile.fetch("id"))
    user.update!(login: profile.fetch("login"), name: profile["name"],
      email: profile["email"], avatar_url: profile["avatar_url"], github_token: token,
      github_refresh_token: refresh_token, github_token_expires_at: expires_at)
    user
  end

  def display_name
    name.presence || login
  end

  def admin?
    github_id == OWNER_GITHUB_ID
  end

  def self.github_allowed?(github_id)
    id = Integer(github_id.to_s, 10)
    id == OWNER_GITHUB_ID || GithubAccessGrant.exists?(github_id: id)
  rescue ArgumentError, TypeError
    false
  end

  def login_allowed?
    self.class.github_allowed?(github_id)
  end
end
