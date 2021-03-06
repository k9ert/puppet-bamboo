#
# Notes on conf/wrapper.conf settings:
# wrapper.java.additional.3=-Xms256m              <- Initial Heap Size
# wrapper.java.additional.4=-Xmx512m              <- Max Heap Size
# wrapper.java.additional.5=-XX:MaxPermSize=256m  <- Max PermGen Size
#
# Usage:
#
# class { 'bamboo::server':
#   version              => '5.2.2',            # default shown
#   atlassian_vendor_dir => '/opt/atlassian',
#                             ^^ where to vendor atlassian products,
#                                default shown
#
#   user                 => 'bamboouser',    # should be a valid file path
#   group                => $user,              # default shown
#   home                 => "/home/bamboouser/bamboo-home",
#                             ^^ where config files are stored, default shown
#
#   log_dir              => "/home/bamboouser/bamboo-home/log", # default shown
#   run_dir              => "/var/run/bamboo.pid"  # default shown
# }
class bamboo::server (

  $version              = '4.2.0',
  $atlassian_vendor_dir = '/opt/atlassian',
  $user                 = 'bamboouser',
  $group                = 'bamboouser',
  $home                 = '/home/bamboouser/bamboo-home',
  $log_dir              = '/home/bamboouser/bamboo-home/log',
  $run_dir              = '/var/run/bamboo.pid',
  $port                 = '8085'

) {

  $bamboo_group = $group ? { 'undefined' => $user, default =>  $group }
  $bamboo_home  = $home ? { 'undefined' => "/var/lib/${user}", default => $home }
  $bamboo_tgz   = "atlassian-bamboo-${version}.tar.gz"
  $download_url = "http://www.atlassian.com/software/bamboo/downloads/binary/${bamboo_tgz}"

  if ! defined( File[ $atlassian_vendor_dir ] ) {
    file { $atlassian_vendor_dir: ensure => directory }
  }

  Exec {
    path      => [ '/bin', '/usr/bin', '/usr/local/bin' ],
    logoutput => on_failure,
  }

  exec { 'download-bamboo-server':
    command => "wget ${download_url}",
    cwd     => $atlassian_vendor_dir,
    timeout => 120,
    creates => "${atlassian_vendor_dir}/${bamboo_tgz}",
    require => File[ $atlassian_vendor_dir ],
  }

  exec { 'extract-bamboo-server':
    command => "tar -xf ${bamboo_tgz}",
    cwd     => $atlassian_vendor_dir,
    require => Exec[ 'download-bamboo-server' ],
    creates => "${atlassian_vendor_dir}/atlassian-bamboo-${version}",
  }

  file { 'bamboo.current.link':
    ensure  => link,
    path    => "/opt/atlassian-bamboo",
    target  => "${atlassian_vendor_dir}/atlassian-bamboo-${version}",
    require => Exec[ 'extract-bamboo-server' ],
  }

  file { '/opt/atlassian-bamboo/logs/':
    ensure  => directory,
    owner   => $user,
    require => Exec[ 'extract-bamboo-server' ],
  }


  group { $bamboo_group: ensure => present }

  user { $user:
    gid     => $bamboo_group,
    home    => $bamboo_home,
    require => Group[ $bamboo_group ],
  }

  file { $bamboo_home:
    ensure  => directory,
    owner   => $user,
    require => User[ $user ],
  }

  file_line { 'set-bamboo-init.properties':
    path    => "${atlassian_vendor_dir}/atlassian-bamboo-${version}/atlassian-bamboo/WEB-INF/classes/bamboo-init.properties",
    line    => "bamboo.home=${bamboo_home}",
    match   => '^#?bamboo.home=.*$',
    require => Exec[ 'extract-bamboo-server' ],
  }

  file_line { 'set-bamboo-session-timeout':
    path    => "${atlassian_vendor_dir}/atlassian-bamboo-${version}/atlassian-bamboo/WEB-INF/web.xml",
    line    => "    <session-timeout>0</session-timeout>",
    match   => '    <session-timeout>\d+</session-timeout>',
    require => Exec[ 'extract-bamboo-server' ],
  }

  file { '/etc/init.d/bamboo':
    ensure  => present,
    path    => '/etc/init.d/bamboo',
    content => template('bamboo/bamboo-init.sh.erb'),
    mode    => '0755',
    require => Exec[ 'extract-bamboo-server' ],
  }

  if ! defined( File[ '/etc/default' ] ) {
    file { '/etc/default': ensure => directory }
  }

  file { '/etc/default/bamboo':
    ensure  => present,
    content => template( 'bamboo/defaults.erb' ),
    require => [ File[ '/etc/default' ],
                 File[ "/etc/init.d/bamboo" ],
                 File_line[ 'set-bamboo-init.properties' ] ],
  }

  file_line { 'bamboo-server-conf-port':
    path    => "${atlassian_vendor_dir}/atlassian-bamboo-${version}/conf/wrapper.conf",
    match   => '^wrapper\.app\.parameter\.2=.*',
    line    => "wrapper.app.parameter.2=${port}",
    require => Exec[ 'extract-bamboo-server' ],
  }

  file { "${run_dir}/${user}":
    ensure  => directory,
    owner   => $user,
    require => User[ $user ],
  }

  file { "${log_dir}/bamboo":
    ensure  => directory,
    owner   => $user,
    require => User[ $user ],
  }

  service { "bamboo":
    ensure  => running,
    enable  => true,
    require => [ File[ '/etc/default/bamboo' ],
                 File[ "${run_dir}/${user}" ],
                 File[ "${log_dir}/bamboo" ] ],
  }
}
