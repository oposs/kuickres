package Kuickres::Email;

use Mojo::Base -base,-signatures;
use Email::MIME;
use Email::Sender::Simple;
use Mojo::Template;
use Mojo::Util qw(dumper);
use CallBackery::Exception qw(mkerror);
use CallBackery::Translate qw(trm);
has app => sub {
    die "app property must be set";
};

has log => sub ($self) {
    $self->app->log;
};

has home => sub ($self) {
    $self->app->home;
};

has template => sub ($self) {
    Mojo::Template->new(
        vars => 1,
    );
};

sub getText ($self,$template,$args) {
    my ($head,$text,$html) = split /\n-{4}\s*\n/, 
        $self->template->render_file(
            $self->home->child('templates',$template.'.email.ep'),
        $args),3;
    my %headers;
    while ($head =~ m/(\S+):\s+(.+(:?\n\s.+)*)/g){
        $headers{$1} = $2;
        $headers{$1} =~ s/\n\s+/ /g;
    }
    return {
        head => \%headers,
        text => $text."\n",
        html => $html
    }
}

=head2 sendMail($cfg)

    from => x,
    to => y,
    template => z,
    arguments => { ... }

=cut

sub sendMail ($self,$cfg) {

    my $in = $self->getText($cfg->{template},$cfg->{args});
    eval {
        my $msg = Email::MIME->create(
            header_str => [
                %{$in->{head}},
                To      => $cfg->{to},
                From    => $cfg->{from},
            ],
            attributes  => {
                content_type => "multipart/alternative",
            },
            parts => [
                Email::MIME->create(
                    attributes => {
                        content_type => "text/plain",
                        disposition  => "inline",
                        encoding     => "quoted-printable",
                        charset      => "UTF-8",
                    },
                    body_str => $in->{text},
                ),
                Email::MIME->create(
                    attributes => {
                        content_type => "text/html",
                        disposition  => "inline",
                        encoding     => "quoted-printable",
                        charset      => "UTF-8",
                    },
                    body_str => $in->{html},
                )
            ]
        );
        Email::Sender::Simple->send($msg);
        $self->log->debug("Mail sent to $cfg->{to} ($in->{head}{Subject})");
    };
    if ($@) {
        $self->log->warn($@);
        die mkerror(7474,trm("Failed to send mail to %1",$cfg->{to}));
    }
}

1;