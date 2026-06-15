require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))
repository_url = package.dig('repository', 'url').to_s.sub(/^git\+/, '')
homepage_url = repository_url.sub(/\.git$/, '')

Pod::Spec.new do |s|
  s.name = 'CapacitorLabelPrinter'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = homepage_url
  s.author = package['author']
  s.source = { git: repository_url, tag: s.version.to_s }
  s.source_files = 'ios/Plugin/**/*.{swift,h,m,mm}'
  s.preserve_paths = 'ios/VendorFrameworks/**/*'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
