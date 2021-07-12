package Kuickres::Model::Email;

use Mojo::Base -base,-signatures;
use Email::MIME;
use Email::Sender::Simple;
use Mojo::Template;
use Mojo::Util qw(dumper);
use Mojo::URL;
use CallBackery::Exception qw(mkerror);
use CallBackery::Translate qw(trm);
use Email::Sender::Transport::SMTP;
use Email::Address;

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

has bcfg => sub ($self) {
    $self->app->config->cfgHash->{BACKEND};
};

has smtp => sub ($self) {
    $self->bcfg->{smtp_url};
};

has bcc => sub ($self) {
    $self->bcfg->{bcc};
};

has envelope_from => sub ($self) {
    $self->bcfg->{from};
};

has sender_address => sub ($self) {
    $self->envelope_from;
};

has mailTransport => sub ($self) {
    my $mt = $self->app->mailTransport;
    if (not $mt and $self->smtp) {
        my $smtp = Mojo::URL->new($self->smtp);
        $mt = Email::Sender::Transport::SMTP->new({
            host => $smtp->host,
            port => $smtp->port || 587,
            ssl => 'starttls',
            $smtp->username ? (
                sasl_username => $smtp->username,
                sasl_password => $smtp->password
            ):()
        });
        $self->log->debug("Sending mail via ".$smtp->host);
    }
    return $mt;
};

sub getText ($self,$template,$args) {
    my $render = $self->template->render_file(
        $self->home->child('templates',$template.'.email.ep'),
        $args);
    if (ref $render eq 'Mojo::Exception') {
        die("Faild to process $template: ".$render->message);
    }
    my ($head,$text,$html) = split /\n-{4}\s*\n/,$render,3;
    my %headers;
    while ($head =~ m/(\S+):\s+(.+(:?\n\s.+)*)/g){
        $headers{$1} = $2;
        $headers{$1} =~ s/\n\s+/ /g;
    }
    if (not $headers{Subject}) {
        $self->log->error('Subject header is missing: '.dumper(\%headers));
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
    my $from = $cfg->{from} || $self->sender_address;
    my @bcc = map { $_->address } ($self->bcc ? (Email::Address->parse($self->bcc)) : ());
    if ($cfg->{bcc}){
        push @bcc, $cfg->{bcc};
    }
    if ($ENV{OVERRIDE_TO}) {
        $self->log->info("Overriding $cfg->{to} with $ENV{OVERRIDE_TO}");
        $cfg->{to} = $ENV{OVERRIDE_TO};
        @bcc=();
    }
    my $to = $cfg->{to};
    eval {
        my $msg = Email::MIME->create(
            header_str => [
                %{$in->{head}},
                To      => $to,
                From    => $from
            ],
            attributes  => {
                content_type => "multipart/mixed",
            },
            parts => [
                Email::MIME->create(
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
                ),
                map {
                   Email::MIME->create(
                    attributes => {
                        encoding     => "quoted-printable",
                        %{$_->{attributes}},
                    },
                    body =>  $_->{body}
                   );
                } @{$cfg->{attachements}//[]}
            ],
        );
        my @froms = Email::Address->parse($self->envelope_from || $cfg->{from});
        my %MT = (
            to => [$to, @bcc],
            from => $froms[0]->address,
        );
        if ($self->mailTransport) {
            $MT{transport} = $self->mailTransport
        }
        Email::Sender::Simple->send($msg,\%MT);
        $self->log->debug("Mail sent ".$froms[0]->address." to $cfg->{to} ($in->{head}{Subject})");
    };
    if ($@) {
        $self->log->warn($@);
        die mkerror(7474,trm("Failed to send mail to %1",$cfg->{to}));
    }
}

1;