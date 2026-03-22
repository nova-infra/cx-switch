#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "pathname"
require "time"

APP_SUPPORT = File.expand_path("~/Library/Application Support/com.novainfra.cx-switch")
DEFAULT_REGISTRY = File.join(APP_SUPPORT, "registry.json")

def load_registry(path)
  payload = JSON.parse(File.read(path))
  payload.is_a?(Hash) ? payload.fetch("accounts", []) : payload
end

def decode_stored_auth(encoded)
  return nil if encoded.nil? || encoded.empty?

  JSON.parse(Base64.decode64(encoded))
rescue StandardError
  nil
end

def auth_identity(blob)
  return {} unless blob.is_a?(Hash)

  tokens = blob["tokens"].is_a?(Hash) ? blob["tokens"] : {}
  {
    "auth_mode" => blob["auth_mode"],
    "last_refresh" => blob["last_refresh"],
    "account_id" => tokens["account_id"],
    "refresh_token_present" => !tokens["refresh_token"].to_s.empty?,
    "access_token_present" => !tokens["access_token"].to_s.empty?,
    "id_token_present" => !tokens["id_token"].to_s.empty?
  }
end

registry_path = ARGV[0] || DEFAULT_REGISTRY
abort("registry not found: #{registry_path}") unless File.exist?(registry_path)

accounts = load_registry(registry_path)
now = Time.now.utc.iso8601

puts "SQLite migration audit"
puts "registry: #{registry_path}"
puts "accounts: #{accounts.length}"
puts

duplicate_ids = accounts.group_by { |row| row["id"].to_s }.select { |_, rows| rows.length > 1 }
duplicate_emails = accounts.group_by { |row| row["email"].to_s.downcase }.select { |key, rows| !key.empty? && rows.length > 1 }
current_rows = accounts.select { |row| row["isCurrent"] == true }
missing_credentials = []
keychain_fallback = []

accounts.each_with_index do |row, index|
  stored_auth_blob = decode_stored_auth(row["storedAuth"])
  identity = auth_identity(stored_auth_blob)
  has_stored_auth = !stored_auth_blob.nil?
  needs_keychain = !has_stored_auth && !row["authKeychainKey"].to_s.empty?
  missing_credentials << row unless has_stored_auth || needs_keychain
  keychain_fallback << row if needs_keychain

  puts "[#{index}] id=#{row["id"]}"
  puts "    email=#{row["email"]}"
  puts "    chatgpt_account_id=#{row["chatgptAccountId"] || "-"}"
  puts "    current=#{row["isCurrent"] == true}"
  puts "    usage_snapshot=#{row.key?("usageSnapshot")}"
  puts "    credential_source=#{has_stored_auth ? "storedAuth" : (needs_keychain ? "keychain" : "missing")}"
  if has_stored_auth
    puts "    auth_mode=#{identity["auth_mode"] || "-"}"
    puts "    auth_account_id=#{identity["account_id"] || "-"}"
    puts "    refresh_token=#{identity["refresh_token_present"]}"
    puts "    last_refresh=#{identity["last_refresh"] || now}"
  end
end

puts
puts "Summary"
puts "  duplicate_ids=#{duplicate_ids.length}"
puts "  duplicate_emails=#{duplicate_emails.length}"
puts "  current_rows=#{current_rows.length}"
puts "  missing_credentials=#{missing_credentials.length}"
puts "  keychain_fallback_needed=#{keychain_fallback.length}"

unless duplicate_ids.empty?
  puts
  puts "Duplicate IDs"
  duplicate_ids.each do |id, rows|
    puts "  #{id}: #{rows.length}"
  end
end

unless duplicate_emails.empty?
  puts
  puts "Duplicate Emails"
  duplicate_emails.each do |email, rows|
    puts "  #{email}: #{rows.length}"
  end
end

unless missing_credentials.empty?
  puts
  puts "Accounts missing both storedAuth and authKeychainKey"
  missing_credentials.each do |row|
    puts "  #{row["id"]} #{row["email"]}"
  end
end
