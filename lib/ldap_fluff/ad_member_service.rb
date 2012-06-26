require 'net/ldap'

# Naughty bits of active directory ldap queries
class LdapFluff::ActiveDirectory::MemberService

  attr_accessor :ldap

  def initialize(ldap,group_base)
    @ldap = ldap
    @group_base = group_base
  end

  # get a list [] of ldap groups for a given user
  # in active directory, this means a recursive lookup
  def find_user_groups(uid)
    name_filter = Net::LDAP::Filter.eq("samaccountname",uid)
    @data = @ldap.search(:filter => name_filter)
    raise UIDNotFoundException if @data == nil
    _groups_from_ldap_data(@data.first)
  end

  # return the :memberof attrs + parents, recursively
  def _groups_from_ldap_data(payload)
    total_groups = _group_names_from_cn(payload[:memberof])
    first_level = total_groups
    first_level.each do |g|
      total_groups += _walk_group_ancestry([g])
    end
    total_groups.uniq
  end

  # recursively loop over the parent list
  def _walk_group_ancestry(gids=[])
    set = []
    gids.each do |g|
      filter = group_filter(g) & class_filter
      group = @ldap.search(:filter => filter, :base => @group_base).first
      begin
        set += _group_names_from_cn(group[:memberof])
      rescue Exception
        return []
      end
      set += _walk_group_ancestry(set)
    end
    set
  end

  def group_filter(gid)
    Net::LDAP::Filter.eq("cn", gid)
  end

  def class_filter
    Net::LDAP::Filter.eq("objectclass","group")
  end

  # extract the group names from the LDAP style response,
  # return string will be something like
  # CN=bros,OU=bropeeps,DC=jomara,DC=redhat,DC=com
  #
  # AD group proc from
  # http://erniemiller.org/2008/04/04/simplified-active-directory-authentication/
  #
  # I think we would normally want to just do the collect at the end,
  # but we need the individual names for recursive queries
  def _group_names_from_cn(grouplist)
    p = Proc.new { |g| g.sub(/.*?CN=(.*?),.*/, '\1') }
    grouplist.collect(&p)
  end

  class UIDNotFoundException < StandardError
  end
end