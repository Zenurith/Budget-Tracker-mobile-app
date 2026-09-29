"""Private, deterministic English parser. Never saves a transaction implicitly."""
import re
from datetime import date, timedelta
from decimal import Decimal
from .errors import DomainError, ErrorKind

WORDS = {
    'Food': ('lunch', 'dinner', 'breakfast', 'coffee', 'food', 'restaurant', 'groceries', 'grocery', 'cafe'),
    'Transport': ('taxi', 'grab', 'uber', 'bus', 'train', 'petrol', 'fuel', 'parking', 'transport'),
    'Shopping': ('shopping', 'clothes', 'shoes', 'shirt', 'amazon'),
    'Bills': ('rent', 'electricity', 'internet', 'phone', 'bill', 'water'),
    'Entertainment': ('movie', 'cinema', 'netflix', 'game', 'spotify'),
    'Health': ('doctor', 'medicine', 'pharmacy', 'clinic', 'gym'),
    'Salary': ('salary', 'paycheck', 'wages'),
    'Other income': ('freelance', 'bonus', 'refund', 'gift'),
}


def parse(text, reference_date, categories):
    lower = text.lower()
    when = reference_date
    iso = re.search(r'\b\d{4}-\d{2}-\d{2}\b', lower)
    if iso:
        try:
            when = date.fromisoformat(iso.group())
        except ValueError:
            raise DomainError(ErrorKind.INVALID_INPUT, 'Please enter a valid date.')
        lower = lower.replace(iso.group(), '')
    elif 'yesterday' in lower:
        when -= timedelta(days=1)
    elif 'tomorrow' in lower:
        when += timedelta(days=1)
    elif re.search(r'\b(last|on)\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', lower):
        weekday = re.search(r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', lower).group()
        offset = (when.weekday() - ['monday','tuesday','wednesday','thursday','friday','saturday','sunday'].index(weekday)) % 7
        when -= timedelta(days=offset or 7)
    amounts = re.findall(r'(?<![\w.\-])(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?(?![\w.])', lower)
    if len(amounts) != 1:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Please include exactly one amount, for example: Spent 15.50 on lunch yesterday.')
    amount = int(Decimal(amounts[0].replace(',', '')) * 100)
    if amount <= 0 or amount > 100_000_000_000:
        raise DomainError(ErrorKind.INVALID_INPUT, 'Please enter a positive amount within the supported range.')
    kind = 'income' if re.search(r'\b(earned|received|salary|paycheck|wages|income|refund|bonus)\b', lower) else 'expense'
    candidates = [c for c in categories if c['type'] == kind]
    selected = next((c for c in candidates if re.search(r'\b' + re.escape(c['name'].lower()) + r'\b', lower)), None)
    if not selected:
        selected = next((c for c in candidates if any(re.search(r'\b' + re.escape(w) + r'\b', lower) for w in WORDS.get(c['name'], ()))), None)
    confident = selected is not None
    selected = selected or next((c for c in candidates if c['name'].startswith('Other')), candidates[0])
    warnings = [] if confident else ['Category is an estimate. Please check it before saving.']
    if not iso and not re.search(r'\b(today|yesterday|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', lower):
        warnings.append('No supported date found; using today. You can change it below.')
    return {'transaction': {'amount': amount, 'type': kind, 'category_id': selected['id'], 'date': when.isoformat(), 'note': text, 'payment_method': 'Cash', 'source': 'nlp'}, 'warnings': warnings}
