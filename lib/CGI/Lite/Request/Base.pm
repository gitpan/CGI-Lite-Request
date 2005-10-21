package CGI::Lite::Request::Base;

use URI;
use File::Type    ();
use HTTP::Headers ();

use CGI::Lite::Request::Cookie;
use CGI::Lite::Request::Upload;

use base qw(CGI::Lite);

our %_instances = ();

sub instance { $_instances{$$} ? $_instances{$$} : $_[0]->new }

sub new {
    my $class = shift;
    $self = $class->SUPER::new();

    if ($^O eq 'darwin') {
        $self->set_platform('Mac');
    }
    elsif ($^O eq 'MSWin32') {
        $self->set_platform('Windows');
    }
    else {
        $self->set_platform('Unix');
    }

    bless $self, $class;

    $_instances{$$} = $self;
    return $self;
}

sub headers { $_[0]->{_headers} }

sub content_encoding { shift->headers->content_encoding(@_) }
sub content_length   { shift->headers->content_length(@_)   }
sub content_type     { shift->headers->content_type(@_)     }
sub header           { shift->headers->header(@_)           }

sub method     { $ENV{REQUEST_METHOD}  }
sub referer    { $ENV{HTTP_REFERER}    }
sub address    { $ENV{REMOTE_ADDR}     }
sub hostname   { $ENV{REMOTE_HOST}     }
sub protocol   { $ENV{SERVER_PROTOCOL} }
sub user       { $ENV{REMOTE_USER}     }
sub user_agent { $ENV{HTTP_USER_AGENT} }

sub parse {
    my $self = shift;

    undef($self->{$_}) for qw[
        _base
        _secure
        _headers
        _cookies
        _path_info
    ];
    $self->{_uploads} = { };

    $self->{_headers} = HTTP::Headers->new(
        Status            => '200 OK',
        Content_Type      => 'text/html',
        Pragma            => 'no-cache',
        Cache_Control     => 'no-cache',
        Connection        => 'close',
    );

    $self->{_cookies} = CGI::Lite::Request::Cookie->fetch;
    $self->set_file_type('handle');
    $self->parse_new_form_data(@_);
}

sub args {
    my $self = shift;
    wantarray ? %{$self->{web_data}} : $self->{web_data};
}

sub param {
    my $self = shift;
    my $key  = shift;
    if (wantarray and ref $self->args->{$key} eq 'ARRAY') {
        return @{$self->{web_data}->{$key}};
    } else {
        return $self->{web_data}->{$key};
    }
}

sub params {
    my $self = shift;
    return @{$self->{web_data}}{$self->get_ordered_keys};
}

sub uri {
    my ($self) = @_;
    return join('', $self->base, $self->path_info);
}

sub secure {
    my $self = shift;
    unless (defined $self->{_secure}) {
        if ( $ENV{HTTPS} && uc( $ENV{HTTPS} ) eq 'ON' ) {
            $self->{_secure}++;
        }

        if ( $ENV{SERVER_PORT} == 443 ) {
            $self->{_secure}++;
        }
    }
    $self->{_secure};
}

sub base {
    my $self = shift;
    unless ($self->{_base}) {
        my $base;
        my $scheme = $self->secure ? 'https' : 'http';
        my $host   = $ENV{HTTP_HOST}   || $ENV{SERVER_NAME};
        my $port   = $ENV{SERVER_PORT} || 80;
        my $path   = $ENV{SCRIPT_NAME} || '/';

        unless ( $path =~ /\/$/ ) {
            $path .= '/';
        }

        $base = URI->new;
        $base->scheme($scheme);
        $base->host($host);
        $base->port($port);
        $base->path($path);

        $self->{_base} = $base->canonical->as_string;
    }
    $self->{_base};
}

sub path_info {
    my $self = shift;
    unless ($self->{_path_info}) {
        my $path = $ENV{PATH_INFO} || '/';
        my $location = $ENV{SCRIPT_NAME} || '/';
        $path =~ s/^($location)?\///;
        $path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $path =~ s/^\///;
        $self->{_path_info} = $path;
    }
    $self->{_path_info};
}

sub print {
    my $self = shift;
    CORE::print(@_);
}

sub send_http_header {
    my $self = shift;
    if (my $content_type = shift) {
        $self->content_type($content_type);
    }
    unless ($self->content_type) {
        $self->content_type('text/html');
    }
    $self->headers->header(
        Set_Cookie => join(
            "\n", map {
                $_->as_string
            } values %{$self->cookies}
        )
    );

    $self->print($self->headers->as_string, "\015\012" x 2);
}

sub cookie {
    my ($self, $name) = @_;
    $self->{_cookies}->{$name} ||= CGI::Lite::Request::Cookie->new(
        -name  => $name,
        -value => '',
    );
    return $self->{_cookies}->{$name};
}

sub cookies { $_[0]->{_cookies} }

sub upload {
    my ($self, $fieldname) = @_;
    return $self->uploads->{ $self->param($fieldname) };
}

sub uploads { $_[0]->{_uploads} }

sub _create_handles {
    my ($self, $files) = @_;

    my $ft = File::Type->new;
    my ($upload, $name, $path);
    while (($name, $path) = each %$files) {
        $upload = CGI::Lite::Request::Upload->new;
        $upload->tempname($path);
        $upload->filename($name);
        $upload->type($ft->mime_type($path));
        $upload->size(-s $path);
        $self->{_uploads}->{$name} = $upload;
    }
}

1;

__END__

=head1 NAME

CGI::Lite::Request::Base - Base class for CGI::Lite::Request implementations

=head1 SEE ALSO

L<CGI::Lite>, L<CGI::Lite::Request>
