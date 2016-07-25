# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'shexecutor/version'

Gem::Specification.new do |spec|
  spec.name          = "shexecutor"
  spec.version       = SHExecutor::VERSION
  spec.authors       = ["Ernst van Graan"]
  spec.email         = ["ernstvangraan@gmail.com"]
  spec.summary       = %q{Execute shell commands easily and securely}
  spec.description   = %q{Implements process replacement, forking, protection from shell injection, and a variety of output options}
  spec.homepage      = "https://github.com/evangraan/shexecutor"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.required_ruby_version = '>= 2.0'

  spec.add_development_dependency 'bundler', "~> 1.12.5"
  spec.add_development_dependency 'rake', "~> 11.2.2"
  spec.add_development_dependency 'rspec', "~> 3.5.0"
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'simplecov-rcov'
  spec.add_development_dependency 'byebug'
end
