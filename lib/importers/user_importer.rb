# frozen_string_literal: true

require "#{Rails.root}/lib/replica"
require "#{Rails.root}/lib/wiki_api"

#= Imports and updates users from Wikipedia into the dashboard database
class UserImporter
  def self.from_omniauth(auth)
    user = User.find_by(username: auth.info.name)
    user ||= User.find_by(global_id: auth.uid)

    return new_from_omniauth(auth) if user.nil?
    update_user_from_auth(user, auth)
    user
  end

  def self.new_from_omniauth(auth)
    require "#{Rails.root}/lib/wiki_api"

    user = User.create(
      username: auth.info.name,
      global_id: auth.uid,
      wiki_token: auth.credentials.token,
      wiki_secret: auth.credentials.secret
    )
    user
  end

  def self.new_from_username(username)
    # All mediawiki usernames have the first letter capitalized, although
    # the API returns data if you replace it with lower case.
    username = String.new(username)
    # mediawiki mostly treats spaces and underscores as equivalent, but spaces
    # are the canonical form. Replica will not return revisions for the underscore
    # versions.
    username.tr!('_', ' ')
    # Remove any leading or trailing whitespace that snuck through.
    username.gsub!(/^[[:space:]]+/, '')
    username.gsub!(/[[:space:]]+$/, '')
    # TODO: mb_chars for capitalzing unicode should not be necessary with Ruby 2.4
    username[0] = username[0].mb_chars.capitalize.to_s unless username.empty?

    user = User.find_by(username: username)
    return user if user

    # All users are expected to have an account on the central wiki, no matter
    # which is their home wiki.
    return unless user_exists_on_meta?(username)

    # We may already have a user record, but the user has been renamed.
    # We check for a user with the same global_id, and update the username if
    # we find one.
    update_username_for_global_id(username)

    # At this point, if we still can't find a record with this username,
    # we finally create and return it.
    return User.find_or_create_by(username: username)
  end

  def self.update_users(users=nil)
    users ||= User.all
    users.each do |user|
      update_user_from_metawiki(user)
    end
  end

  ##################
  # Helper methods #
  ##################

  def self.update_user_from_auth(user, auth)
    user.update(global_id: auth.uid,
                username: auth.info.name,
                wiki_token: auth.credentials.token,
                wiki_secret: auth.credentials.secret)
  end

  def self.user_exists_on_meta?(username)
    WikiApi.new(MetaWiki.new).get_user_id(username).present?
  end

  def self.update_username_for_global_id(username)
    existing_user = user_with_same_global_id(username)
    existing_user&.update_attribute(:username, username)
  end

  def self.user_with_same_global_id(username)
    global_id = get_global_id(username)
    return unless global_id
    User.find_by(global_id: global_id)
  end

  def self.get_global_id(username)
    user_data = WikiApi.new(MetaWiki.new).get_user_info(username)
    user_data&.dig('centralids', 'CentralAuth')
  end

  def self.update_user_from_metawiki(user)
    user_data = WikiApi.new(MetaWiki.new).get_user_info(user.username)
    user.update!(username: user_data['name'],
                 registered_at: user_data['registration'],
                 global_id: user_data['centralids']['CentralAuth'])
  end
end
