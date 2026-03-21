#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "CXSwitch.xcodeproj")
PROJECT_NAME = "CXSwitch"
BUNDLE_ID = "com.novainfra.cx-switch"
DEPLOYMENT_TARGET = "14.0"

source_files = [
  "CXSwitch/CXSwitchApp.swift",
  "CXSwitch/Models/Account.swift",
  "CXSwitch/Models/AuthBlob.swift",
  "CXSwitch/Models/AppState.swift",
  "CXSwitch/Models/LoginFlowState.swift",
  "CXSwitch/Models/Preferences.swift",
  "CXSwitch/Models/UsageSnapshot.swift",
  "CXSwitch/Services/AccountStore.swift",
  "CXSwitch/Services/AuthService.swift",
  "CXSwitch/Services/CodexAppServer.swift",
  "CXSwitch/Services/KeychainService.swift",
  "CXSwitch/Services/UsageProbe.swift",
  "CXSwitch/Utilities/EmailMasker.swift",
  "CXSwitch/Utilities/JWTDecoder.swift",
  "CXSwitch/Utilities/Strings.swift",
  "CXSwitch/Views/CurrentAccountSection.swift",
  "CXSwitch/Views/FooterActions.swift",
  "CXSwitch/Views/LoginFlowSheet.swift",
  "CXSwitch/Views/MenuBarView.swift",
  "CXSwitch/Views/SavedAccountRow.swift",
  "CXSwitch/Views/UsageBar.swift"
]

resource_files = [
  "CXSwitch/Resources/AppIcon.icns"
]

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)

main_group = project.main_group
app_group = main_group.new_group(PROJECT_NAME)
models_group = app_group.new_group("Models")
services_group = app_group.new_group("Services")
utilities_group = app_group.new_group("Utilities")
views_group = app_group.new_group("Views")
resources_group = app_group.new_group("Resources")

target = project.new_target(:application, PROJECT_NAME, :osx, DEPLOYMENT_TARGET)
app_intents_framework = project.frameworks_group.new_file("System/Library/Frameworks/AppIntents.framework")
target.frameworks_build_phase.add_file_reference(app_intents_framework)

target.build_configurations.each do |config|
  settings = config.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = BUNDLE_ID
  settings["INFOPLIST_FILE"] = "CXSwitch/Resources/Info.plist"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["MACOSX_DEPLOYMENT_TARGET"] = DEPLOYMENT_TARGET
  settings["CODE_SIGN_STYLE"] = "Manual"
  settings["CODE_SIGNING_ALLOWED"] = "NO"
  settings["CODE_SIGNING_REQUIRED"] = "NO"
  settings["DEVELOPMENT_TEAM"] = ""
  settings["SWIFT_VERSION"] = "6.0"
  settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/../Frameworks"]
  settings["PRODUCT_NAME"] = PROJECT_NAME
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["MARKETING_VERSION"] = "0.1.0"
  settings["ONLY_ACTIVE_ARCH"] = "NO"
end

group_for_path = lambda do |path|
  case path
  when %r{\ACXSwitch/Models/}
    models_group
  when %r{\ACXSwitch/Services/}
    services_group
  when %r{\ACXSwitch/Utilities/}
    utilities_group
  when %r{\ACXSwitch/Views/}
    views_group
  when %r{\ACXSwitch/Resources/}
    resources_group
  else
    app_group
  end
end

source_files.each do |path|
  file_ref = group_for_path.call(path).new_file(path)
  target.source_build_phase.add_file_reference(file_ref)
end

resource_files.each do |path|
  file_ref = resources_group.new_file(path)
  target.resources_build_phase.add_file_reference(file_ref)
end

project.save
