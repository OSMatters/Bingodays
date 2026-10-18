#!/usr/bin/env ruby
# Checks the FINAL compiled bundle, not just source assets. Also accepts .xcarchive.
require 'json'
require 'open3'

bundle = ARGV.fetch(0) { abort 'Usage: ruby scripts/verify_app_icons.rb <Bingodays.app|archive.xcarchive>' }
bundle = File.join(bundle, 'Products/Applications/Bingodays.app') if bundle.end_with?('.xcarchive')

def read_json(*command)
  output, errors, status = Open3.capture3(*command)
  abort "error: App icon verification failed: #{errors}" unless status.success?
  JSON.parse(output)
end

info = read_json('/usr/bin/plutil', '-convert', 'json', '-o', '-', File.join(bundle, 'Info.plist'))
assets = read_json('/usr/bin/xcrun', 'assetutil', '--info', File.join(bundle, 'Assets.car'))
expected = %w[AppIcon AppIconHalloween AppIcon10Days AppIcon20Days AppIcon30Days AppIconPremium]
previews = %w[AppIconPreviewDefault AppIconPreviewHalloween AppIconPreview10Days AppIconPreview20Days AppIconPreview30Days AppIconPreviewPremium]
failures = []

# Catalog-only alternate entries are valid. If an entry ALSO declares standalone
# files, each basename must resolve in the final bundle, not just in source assets.
def icon_file_exists?(bundle, name)
  return false unless name.is_a?(String) && !name.empty? && File.basename(name) == name

  extension = File.extname(name)
  basename = extension.empty? ? name : name.delete_suffix(extension)
  extension = '.png' if extension.empty?
  suffixes = ['', '@2x', '@3x', '~iphone', '@2x~iphone', '@3x~iphone', '~ipad', '@2x~ipad', '@3x~ipad']
  suffixes.any? { |suffix| File.file?(File.join(bundle, "#{basename}#{suffix}#{extension}")) }
end

%w[CFBundleIcons CFBundleIcons~ipad].each do |key|
  icons = info.fetch(key, {})
  primary = icons.fetch('CFBundlePrimaryIcon', {}).fetch('CFBundleIconName', nil)
  alternates = icons.fetch('CFBundleAlternateIcons', {})
  failures << "#{key}: unexpected primary icon #{primary.inspect}" unless expected.include?(primary)
  (expected - [primary]).each do |name|
    entry = alternates[name]
    failures << "#{key}: #{name} is not registered with matching CFBundleIconName" unless entry && entry['CFBundleIconName'] == name
  end
  entries = alternates.merge('CFBundlePrimaryIcon' => icons.fetch('CFBundlePrimaryIcon', {}))
  entries.each do |name, entry|
    next unless entry.key?('CFBundleIconFiles')

    files = entry['CFBundleIconFiles']
    unless files.is_a?(Array) && !files.empty?
      failures << "#{key}: #{name} has invalid CFBundleIconFiles"
      next
    end
    files.each do |file|
      failures << "#{key}: #{name} references missing icon file #{file.inspect}" unless icon_file_exists?(bundle, file)
    end
  end
end

expected.each do |name|
  valid = assets.any? do |asset|
    asset['Name'] == name && asset['AssetType'] == 'Icon Image' &&
      asset.fetch('PixelWidth', 0) > 0 && asset['PixelHeight'] == asset['PixelWidth']
  end
  failures << "Assets.car: #{name} has no compiled icon rendition" unless valid
end
previews.each do |name|
  valid = assets.any? { |asset| asset['Name'] == name && asset['AssetType'] == 'Image' && asset.fetch('PixelWidth', 0) > 0 && asset.fetch('PixelHeight', 0) > 0 }
  failures << "Assets.car: #{name} has no compiled preview image" unless valid
end

unless failures.empty?
  failures.each { |failure| warn "error: App icon verification: #{failure}" }
  exit 1
end
puts "App icon verification PASS: #{info['CFBundleShortVersionString']} (#{info['CFBundleVersion']}), six icons/previews, iPhone + iPad registrations"
