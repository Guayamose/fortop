require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  Capybara.register_driver :fortop_headless_chrome do |app|
    Selenium::WebDriver.logger.level = :warn
    options = Selenium::WebDriver::Chrome::Options.new
    options.binary = ENV.fetch("CHROME_BIN", "/usr/bin/google-chrome")
    options.add_argument("--headless=new")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1440,1000")

    cached_driver = Dir.glob(File.expand_path("~/.cache/selenium/chromedriver/linux64/*/chromedriver")).sort.last
    driver_path = ENV["CHROMEDRIVER_PATH"].presence || cached_driver
    service = driver_path ? Selenium::WebDriver::Chrome::Service.new(path: driver_path) : nil
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, **(service ? { service: service } : {}))
  end

  driven_by :fortop_headless_chrome
end
