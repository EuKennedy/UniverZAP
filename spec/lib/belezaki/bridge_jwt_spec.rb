require 'rails_helper'

RSpec.describe Belezaki::BridgeJwt do
  let(:secret) { 'super-secret-shared-key-at-least-32-chars-long' }

  let(:valid_claims) do
    {
      iss: 'belezaki', aud: 'univerzap', sub: 'sub_1', email: 'a@b.com',
      name: 'João', accountName: 'Studio', role: 'ultra',
      iat: Time.current.to_i, exp: Time.current.to_i + 120, jti: SecureRandom.uuid
    }
  end

  def mint(claims, sig_secret: secret, header: { alg: 'HS256', typ: 'JWT' })
    header_seg = Base64.urlsafe_encode64(header.to_json, padding: false)
    payload_seg = Base64.urlsafe_encode64(claims.to_json, padding: false)
    sig = Base64.urlsafe_encode64(
      OpenSSL::HMAC.digest('SHA256', sig_secret, "#{header_seg}.#{payload_seg}"), padding: false
    )
    "#{header_seg}.#{payload_seg}.#{sig}"
  end

  it 'accepts a valid token' do
    result = described_class.verify(jwt: mint(valid_claims), secret: secret)
    expect(result.ok).to be(true)
    expect(result.claims['email']).to eq('a@b.com')
  end

  it 'rejects a tampered signature' do
    result = described_class.verify(jwt: mint(valid_claims, sig_secret: 'wrong-secret'), secret: secret)
    expect(result.reason).to eq('bad_signature')
  end

  it 'rejects an expired token' do
    result = described_class.verify(jwt: mint(valid_claims.merge(exp: Time.current.to_i - 1)), secret: secret)
    expect(result.reason).to eq('expired')
  end

  it 'rejects a wrong issuer' do
    result = described_class.verify(jwt: mint(valid_claims.merge(iss: 'evil')), secret: secret)
    expect(result.reason).to eq('bad_issuer')
  end

  it 'rejects a wrong audience' do
    result = described_class.verify(jwt: mint(valid_claims.merge(aud: 'other')), secret: secret)
    expect(result.reason).to eq('bad_audience')
  end

  it 'rejects a non-ultra role' do
    result = described_class.verify(jwt: mint(valid_claims.merge(role: 'basic')), secret: secret)
    expect(result.reason).to eq('bad_role')
  end

  it 'rejects a malformed token' do
    expect(described_class.verify(jwt: 'not.a.jwt.x', secret: secret).reason).to eq('malformed')
  end
end
