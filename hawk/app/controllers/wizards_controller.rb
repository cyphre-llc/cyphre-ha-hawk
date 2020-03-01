# Copyright (c) 2009-2015 Tim Serong <tserong@suse.com>
# See COPYING for license.

class WizardsController < ApplicationController
  before_action :login_required
  before_action :set_title
  before_action :set_cib
  before_action :cib_writable
  before_action :cluster_online

  def index
    @wizards = Wizard.all

    respond_to do |format|
      format.html
    end
  end

  def show
    session[:hawk_wizard] = params.to_unsafe_h[:id]
    @wizard = Wizard.find params.to_unsafe_h[:id]
    pa = Rails.cache.read("#{session.id}-#{params.to_unsafe_h[:id]}")
    @wizard.update_step_values(@wizard, pa) if pa

    respond_to do |format|
      format.html
    end
  end

  def update
    @wizard = Wizard.find params.to_unsafe_h[:id]
    pa = build_scriptparams(params)
    @pa = pa
    Rails.cache.write("#{session.id}-#{params.to_unsafe_h[:id]}", pa, expires_in: 1.hour)
    @wizard.verify(pa)

    respond_to do |format|
      format.html
    end
  end

  def submit
    pa = JSON.parse(params.to_unsafe_h[:pa]) if params.to_unsafe_h[:pa]
    pa = Rails.cache.read("#{session.id}-#{params.to_unsafe_h[:id]}") if pa.nil?

    if pa.nil?
      render json: [_("Session has expired")], status: :unprocessable_entity
    else
      @wizard = Wizard.find params.to_unsafe_h[:id]
      @wizard.verify(pa)
      if @wizard.errors.length > 0
        render json: @wizard.errors.to_json, status: :unprocessable_entity
      elsif current_cib.sim? && @wizard.need_rootpw
        render json: [_("Wizard cannot be applied when the simulator is active")], status: :unprocessable_entity
      else
        @wizard.run(pa, params.to_unsafe_h[:rootpw])
        if @wizard.errors.length > 0
          render json: @wizard.errors.to_json, status: :unprocessable_entity
        else
          render json: @wizard.actions
        end
      end
    end
  end

  protected

  def build_stepmap(m, container)
    return m if container.nil?
    container.steps.each { |s| m[s.name] = {} unless s.name.empty? || !s.required }
    m
  end

  def build_scriptparams(params)
    sp = build_stepmap({}, @wizard)
    id = @wizard.id
    params.select { |k, _v| k.start_with?("#{id}.") }.each do |k, v|
      next if v.empty?
      path = k.split(".").drop(1)
      if path.length > 1
        basestep_idx = @wizard.steps.find_index { |x| x.name == path[0] }
        next if basestep_idx.nil?

        basestep = @wizard.steps[basestep_idx]
        next unless basestep.required || (params.key?("enable:#{basestep.id}") && params.to_unsafe_h["enable:#{basestep.id}"] != "false")

        name = path.last
        sub = sp
        path.take(path.length - 1).each do |p|
          sub[p] = {} unless sub.key? p
          sub = sub[p]
        end
        sub[name] = v
      else
        sp[path[0]] = v
      end
    end
    # Rails.logger.debug "scriptparams: #{params} -> #{sp}"
    sp
  end

  def default_base_layout
    "withrightbar"
  end

  protected

  def set_title
    @title = _('Use a wizard')
  end

  def set_cib
    @cib = current_cib
  end

  def cib_writable
    begin
      Invoker.instance.cibadmin("--modify", "--allow-create", "--scope",
        "crm_config", "--xml-text", "<cluster_property_set id=\"hawk-rw-test\"/>")

      Invoker.instance.cibadmin("--delete", "--xml-text", "<cluster_property_set id=\"hawk-rw-test\"/>")
    rescue SecurityError
      respond_to do |format|
        format.html do
          redirect_to(
            cib_url(cib_id: @cib.id),
            alert: _("Permission denied - you do not have write access to the CIB.")
          )
        end
        format.json do
          render json: {
            error: _("Permission denied - you do not have write access to the CIB.")
          }, status: :unprocessable_entity
        end
      end
    rescue NotFoundError => e
      Rails.logger.debug "NotFoundError: #{e}"
    rescue RuntimeError => e
      Rails.logger.debug "RuntimeError: #{e}"
    end
  end

  def cluster_online
    %x[/usr/sbin/crm_mon -s >/dev/null 2>&1]

    if $?.exitstatus == Errno::ENOTCONN::Errno
      respond_to do |format|
        format.html do
          redirect_to(
            cib_url(cib_id: @cib.id),
            alert: _("Cluster seems to be offline")
          )
        end
        format.json do
          render json: {
            error: _("Cluster seems to be offline")
          }, status: :unprocessable_entity
        end
      end
    end
  end
end
