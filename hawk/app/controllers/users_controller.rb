# Copyright (c) 2009-2015 Tim Serong <tserong@suse.com>
# See COPYING for license.

class UsersController < ApplicationController
  before_action :login_required
  before_action :feature_support
  before_action :set_title
  before_action :set_cib
  before_action :set_record, only: [:edit, :update, :destroy, :show]
  before_action :check_support

  def index
    respond_to do |format|
      format.html
      format.json do
        render json: User.ordered.to_json
      end
    end
  end

  def new
    @title = _("Create ACL Target")
    @user = User.new

    respond_to do |format|
      format.html
    end
  end

  def create
    @title = _("Create ACL Target")
    @user = User.new params.to_unsafe_h[:user]

    respond_to do |format|
      if @user.save
        post_process_for! @user

        format.html do
          flash[:success] = _("ACL target created successfully")
          redirect_to cib_users_url(cib_id: @cib.id)
        end
        format.json do
          render json: @user, status: :created
        end
      else
        format.html do
          render action: "new"
        end
        format.json do
          render json: @user.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def edit
    @title = _("Edit ACL Target")

    respond_to do |format|
      format.html
    end
  end

  def update
    @title = _("Edit ACL Target")

    if params.to_unsafe_h[:revert]
      return redirect_to edit_cib_user_url(cib_id: @cib.id, id: @user.id)
    end

    respond_to do |format|
      if @user.update_attributes(params.to_unsafe_h[:user])
        post_process_for! @user

        format.html do
          flash[:success] = _("ACL target updated successfully")
          redirect_to edit_cib_user_url(cib_id: @cib.id, id: @user.id)
        end
        format.json do
          render json: @user, status: :updated
        end
      else
        format.html do
          render action: "edit"
        end
        format.json do
          render json: @user.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    respond_to do |format|
      out, err, rc = Invoker.instance.crm("--force", "configure", "delete", @user.id)
      if rc == 0
        format.html do
          flash[:success] = _("ACL target deleted successfully")
          flash[:warning] = err unless err.blank?
          redirect_to cib_users_url(cib_id: @cib.id)
        end
        format.json do
          render json: {
            success: true,
            message: _("ACL target deleted successfully")
          }
        end
      else
        format.html do
          flash[:alert] = _("Error deleting %s: %s") % [@user.id, err]
          redirect_to cib_users_url(cib_id: @cib.id)
        end
        format.json do
          render json: { error: _("Error deleting %s: %s") % [@user.id, err] }, status: :unprocessable_entity
        end
      end
    end
  end

  def show
    respond_to do |format|
      format.json do
        render json: @user.to_json
      end
      format.any { not_found  }
    end
  end

  protected

  def feature_support
    unless Util.has_feature? :acl_support
      redirect_to root_url, alert: _("ACL is not supported by this cluster.")
    end
  end

  def set_title
    @title = _("ACL Targets")
  end

  def set_cib
    @cib = current_cib
  end

  def set_record
    @user = User.find params.to_unsafe_h[:id]

    unless @user
      respond_to do |format|
        format.html do
          flash[:alert] = _("The ACL target does not exist")
          redirect_to cib_users_url(cib_id: @cib.id)
        end
      end
    end
  end

  def check_support
    flash.now[:warning] = view_context.link_to(
      _("To enable ACLs, set \"enable-acl\" in the Cluster Configuration ('Manage > Configuration')"),
      edit_cib_crm_config_path(cib_id: @cib.id)
    ) unless Util.acl_enabled?
  end

  def post_process_for!(record)
  end

  def default_base_layout
    "withrightbar"
  end

end
