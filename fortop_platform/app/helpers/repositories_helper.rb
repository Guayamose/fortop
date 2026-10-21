module RepositoriesHelper
  LANGUAGE_LOGOS = {
    "html" => "html5", "css" => "css3", "javascript" => "javascript", "typescript" => "typescript",
    "ruby" => "ruby", "python" => "python", "go" => "go", "java" => "java", "kotlin" => "kotlin",
    "swift" => "swift", "c" => "c", "c++" => "cplusplus", "c#" => "csharp", "php" => "php",
    "rust" => "rust", "shell" => "bash", "bash" => "bash", "dart" => "dart", "elixir" => "elixir",
    "vue" => "vuejs", "svelte" => "svelte", "astro" => "astro", "scss" => "sass", "sass" => "sass",
    "hcl" => "terraform", "dockerfile" => "docker", "jupyter notebook" => "jupyter", "r" => "r",
    "lua" => "lua", "markdown" => "markdown", "json" => "json", "yaml" => "yaml", "powershell" => "powershell"
  }.freeze

  def repository_language_logo(language)
    logo = LANGUAGE_LOGOS[language.to_s.strip.downcase]
    if logo
      image_tag "languages/#{logo}.svg", class: "repository-language-logo", alt: "", title: "Lenguaje principal: #{language}", width: 28, height: 28
    else
      app_icon(:code, css_class: "repository-language-logo repository-language-unknown")
    end
  end

  def github_installation_settings_url(installation)
    id = installation.fetch("id")
    if installation.dig("account", "type") == "Organization"
      account = ERB::Util.url_encode(installation.dig("account", "login"))
      "https://github.com/organizations/#{account}/settings/installations/#{id}"
    else
      "https://github.com/settings/installations/#{id}"
    end
  end
end
