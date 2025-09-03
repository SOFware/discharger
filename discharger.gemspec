require_relative "lib/discharger/version"

Gem::Specification.new do |spec|
  spec.name = "discharger"
  spec.version = Discharger::VERSION
  spec.authors = ["Jim Gay", "Savannah Moore"]
  spec.email = ["jim@saturnflyer.com"]
  spec.homepage = "https://github.com/SOFware/discharger"
  spec.summary = "Tasks for discharging an application for deployment."
  spec.description = "Code supporting deployments."

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/SOFware/discharger.git"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.post_install_message = <<~MESSAGE

    Thanks for installing Discharger!
    
    To get started, run the generator in your Rails application:
    
        rails generate discharger:install
    
    This will create a bin/setup script and config/setup.yml file
    to help automate your development environment setup.

  MESSAGE

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "LICENSE", "Rakefile", "README.md", "CHANGELOG.md"]
  end

  spec.add_dependency "open3"
  spec.add_dependency "prism", ">= 0.19.0"
  spec.add_dependency "rails", ">= 7.2.1"
  spec.add_dependency "rainbow"
  spec.add_dependency "reissue"
  spec.add_dependency "slack-ruby-client"
end
