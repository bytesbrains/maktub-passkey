#
# maktub_passkey — iOS plugin podspec.
#
Pod::Spec.new do |s|
  s.name             = 'maktub_passkey'
  s.version          = '0.0.1'
  s.summary          = 'Passkey create/assert + WebAuthn PRF (hmac-secret) for Maktub.'
  s.description      = <<-DESC
Native shim for passkey (WebAuthn/P-256) create + assert and the PRF extension,
used to reproduce a Maktub smartWallet reading key from the passkey (#301).
                       DESC
  s.homepage         = 'https://github.com/nandal/maktub'
  s.license          = { :type => 'MIT', :file => '../LICENSE.md' }
  s.author           = { 'Maktub Protocol' => 'dev@maktub.it' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # PRF (ASAuthorization…PRFRegistrationInputs / PRFAssertionInputs) is iOS 18+;
  # the plugin compiles on the project's min target and gates PRF at runtime.
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
