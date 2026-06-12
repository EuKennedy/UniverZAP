# Direct-upload endpoint for chatflow node media. Unlike the conversation
# uploader, a flow's media is authored before any conversation exists, so we
# only scope by account. Returns the blob (with signed_id) which is stored in
# the node config and later handed to Messages::MessageBuilder at send time.
class Api::V1::Accounts::Chatflows::DirectUploadsController < ActiveStorage::DirectUploadsController
  include EnsureCurrentAccountHelper
  before_action :current_account

  def create
    return if @current_account.nil?

    super
  end
end
