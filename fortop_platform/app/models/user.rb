class User < ApplicationRecord
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
end
