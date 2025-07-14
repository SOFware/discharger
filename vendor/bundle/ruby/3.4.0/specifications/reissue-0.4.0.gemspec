# -*- encoding: utf-8 -*-
# stub: reissue 0.4.0 ruby lib

Gem::Specification.new do |s|
  s.name = "reissue".freeze
  s.version = "0.4.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/SOFware/reissue/blob/main/CHANGELOG.md", "homepage_uri" => "https://github.com/SOFware/reissue", "source_code_uri" => "https://github.com/SOFware/reissue" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jim Gay".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "This gem helps you to prepare for releases of new versions of your code.".freeze
  s.email = ["jim@saturnflyer.com".freeze]
  s.homepage = "https://github.com/SOFware/reissue".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Keep your versions and changelogs up to date and prepared for release.".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rake>.freeze, [">= 0".freeze])
end
