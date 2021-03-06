# JBoss, Home of Professional Open Source
# Copyright 2009, Red Hat Middleware LLC, and individual contributors
# by the @authors tag. See the copyright.txt in the distribution for a
# full listing of individual contributors.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 2.1 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'net/ssh'
require 'net/sftp'
require 'progressbar/progressbar'

module Cantiere
  class SSHHelper
    def initialize( options )
      @options = options

      @exec_helper       = EXEC_HELPER
      @log               = LOG
    end

    def connect
      @log.info "Connecting to #{@options['host']}..."
      @ssh = Net::SSH.start( @options['host'], @options['username'], { :password => @options['password'] } )
    end

    def connected?
      return true if !@ssh.nil? and !@ssh.closed?
      false
    end

    def disconnect
      @log.info "Disconnecting from #{@options['host']}..."
      @ssh.close if connected?
      @ssh = nil
    end

    def upload_files( path, files = {} )

      return if files.size == 0

      raise "You're not connected to server" unless connected?

      global_size = 0

      files.each_value do |file|
        global_size += File.size( file )
      end

      global_size_kb = global_size / 1024
      global_size_mb = global_size_kb / 1024

      @log.info "#{files.size} files to upload (#{global_size_mb > 0 ? global_size_mb.to_s + "MB" : global_size_kb > 0 ? global_size_kb.to_s + "kB" : global_size.to_s})"

      @ssh.sftp.connect do |sftp|

        begin
          sftp.stat!( path )
        rescue Net::SFTP::StatusException => e
          raise unless e.code == 2
          if @options['sftp_create_path']
            @ssh.exec!( "mkdir -p #{path}" )
          else
            raise
          end
        end

        puts

        nb = 0

        files.each do |key, local|
          name       = File.basename( local )
          remote     = "#{path}/#{key}"
          size_b     = File.size( local )
          size_kb    = size_b / 1024
          nb_of      = "#{nb += 1}/#{files.size}"

          begin
            sftp.stat!( remote )

            unless @options['sftp_overwrite']

              local_md5_sum   = `md5sum #{local} | awk '{ print $1 }'`.strip
              remote_md5_sum  = @ssh.exec!( "md5sum #{remote} | awk '{ print $1 }'" ).strip

              if (local_md5_sum.eql?( remote_md5_sum ))
                puts "#{nb_of} #{name}: files are identical (md5sum: #{local_md5_sum}), skipping..."
                next
              end
            end

          rescue Net::SFTP::StatusException => e
            raise unless e.code == 2
          end

          @ssh.exec!( "mkdir -p #{File.dirname( remote ) }" )

          pbar = ProgressBar.new( "#{nb_of} #{name}", size_b )
          pbar.file_transfer_mode

          sftp.upload!( local, remote ) do |event, uploader, *args|
            case event
              when :open then
              when :put then
                pbar.set( args[1] )
              when :close then
              when :mkdir then
              when :finish then
                pbar.finish
            end
          end

          sftp.setstat(remote, :permissions => @options['sftp_default_permissions'])

        end
      end
    end

    def createrepo( path, directories = [] )
      raise "You're not connected to server" unless connected?

      directories.each do |directory|
        @log.info "Refreshing repository information in #{directory}..."
        @ssh.exec!( "createrepo #{path}/#{directory}" )
      end
    end
  end
end
