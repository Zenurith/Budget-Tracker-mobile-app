"""Configurable SMTP delivery; Mailpit is supported only in explicit local mode."""
from email.message import EmailMessage
import os
import smtplib
import ssl
from urllib.parse import urlsplit


class SMTPResetMailer:
    def __init__(self):
        self.host = os.getenv('SMTP_HOST', '')
        self.mode = os.getenv('SMTP_SECURITY', 'starttls')
        self.port = int(os.getenv('SMTP_PORT', '587'))
        self.username = os.getenv('SMTP_USERNAME', '')
        self.password = os.getenv('SMTP_PASSWORD', '')
        self.sender = os.getenv('SMTP_FROM', 'Pocketwise <noreply@localhost>')
        self.reset_url = os.getenv('PASSWORD_RESET_URL', '')
        if self.mode not in ('starttls', 'tls', 'local'):
            raise ValueError('SMTP_SECURITY must be starttls, tls or local.')
        if self.mode == 'local' and self.host not in ('localhost', '127.0.0.1', '::1', 'mailpit'):
            raise ValueError('Unencrypted SMTP is allowed only for the local test inbox.')
        if self.reset_url:
            parsed = urlsplit(self.reset_url)
            if parsed.fragment or parsed.query or (parsed.scheme != 'https' and not
                (parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1'))):
                raise ValueError('PASSWORD_RESET_URL must be HTTPS without query or fragment (localhost HTTP allowed).')

    @property
    def configured(self):
        return bool(self.host)

    def send_reset(self, recipient, token):
        message = EmailMessage()
        message['From'], message['To'] = self.sender, recipient
        message['Subject'] = 'Reset your Pocketwise password'
        text = ('A password reset was requested for your Pocketwise account.\n\n'
                'Open Pocketwise, choose Forgot password, then Enter reset code.\n'
                f'Your single-use reset code is:\n{token}\n\n'
                'It expires in 30 minutes. If you did not request this, ignore this email.\n')
        if self.reset_url:
            text += f'You can also open: {self.reset_url}#reset_token={token}\n'
        message.set_content(text)
        factory = smtplib.SMTP_SSL if self.mode == 'tls' else smtplib.SMTP
        kwargs = {'context': ssl.create_default_context()} if self.mode == 'tls' else {}
        with factory(self.host, self.port, timeout=10, **kwargs) as smtp:
            if self.mode == 'starttls':
                smtp.starttls(context=ssl.create_default_context())
            if self.username:
                smtp.login(self.username, self.password)
            smtp.send_message(message)
