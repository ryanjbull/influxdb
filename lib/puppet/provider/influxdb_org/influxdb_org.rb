# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require_relative '../../../puppet_x/puppetlabs/influxdb/influxdb'

# Implementation for performing initial setup of InfluxDB using the Resource API.
class Puppet::Provider::InfluxdbOrg::InfluxdbOrg < Puppet::ResourceApi::SimpleProvider
  include PuppetX::Puppetlabs::PuppetlabsInfluxdb
  def initialize
    @canonicalized_resources = []
    super
  end

  def canonicalize(_context, resources)
    init_attrs(resources)
    resources
  end

  def get(_context)
    init_auth
    get_org_info
    get_user_info

    response = influx_get('/api/v2/orgs', params: {})
    if response['orgs']
      response['orgs'].reduce([]) do |memo, value|
        org_members = @org_hash.find { |org| org['name'] == value['name'] }.dig('members', 'users')
        memo + [
          {
            name: value['name'],
            ensure: 'present',
            members: org_members ? org_members.map { |member| member['name'] } : [],
            description: value['description']
          },
        ]
      end
    else
      [
        {
          influxdb_host: @influxdb_host,
          org: nil,
          ensure: 'absent',
          description: nil,
        },
      ]
    end
  end

  def create(context, name, should)
    context.debug("Creating '#{name}' with #{should.inspect}")
    body = {
      name: should[:org],
      description: should[:description],
    }
    influx_post('/api/v2/orgs', body.to_s)
  end

  # TODO: make this less ugly
  def update(context, name, should)
    context.debug("Updating '#{name}' with #{should.inspect}")
    org_id = id_from_name(@org_hash, name)
    org_members = @org_hash.find { |org| org['name'] == name }.dig('members', 'users')
    cur_members = org_members ? org_members : []
    should_members = should[:members] ? should[:members] : []

    to_remove = cur_members.map { |member| member['name'] } - should_members
    to_add = should_members - cur_members.map { |member| member['name'] }

    to_remove.each do |user|
      next if user == 'admin'
      user_id = id_from_name(@user_map, user)
      url = "/api/v2/orgs/#{org_id}/members/#{user_id}"
      influx_delete(url)
    end
    to_add.each do |user|
      user_id = id_from_name(@user_map, user)
      body = { name: user, id: user_id }
      url = "/api/v2/orgs/#{org_id}/members"
      influx_post(url, JSON.dump(body))
    end

    body = { description: should[:description], }
    influx_patch("/api/v2/orgs/#{org_id}", JSON.dump(body))
  end

  def delete(context, name)
    context.debug("Deleting '#{name}'")
  end
end
