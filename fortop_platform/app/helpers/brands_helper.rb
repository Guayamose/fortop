module BrandsHelper
  def uploaded_brand_logo_source(brand)
    logo_brand_path(brand, v: brand.logo.blob.id) if brand.persisted? && brand.logo.attached? && brand.logo.blob.persisted?
  end

  def brand_logo_source(brand)
    uploaded_brand_logo_source(brand) || website_brand_logo_source(brand.website)
  end

  def website_brand_logo_source(website)
    return unless Visibility::Urls.public_url(website).present?

    "https://www.google.com/s2/favicons?#{URI.encode_www_form(domain: URI.parse(website).host, sz: 128)}"
  end
end
