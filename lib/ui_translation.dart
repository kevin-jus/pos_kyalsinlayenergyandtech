import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiTranslation {
  UiTranslation._();

  static const _languageKey = 'ui_language';
  static final ValueNotifier<String> language = ValueNotifier<String>('en');

  static const Map<String, String> _my = <String, String>{
      'POS System': 'POS စနစ်',
      'Point of Sale System': 'အရောင်းဆိုင် စီမံခန့်ခွဲမှုစနစ်',
      'Open menu': 'မီနူးဖွင့်ရန်',
      'Pay Yan': 'ပေးရန်',
      'Ya Yan': 'ရရန်',
      'Data Backup': 'ဒေတာ အရန်သိမ်းရန်',
      'Products': 'ကုန်ပစ္စည်းများ',
      'In-stock Products': 'လက်ကျန်ကုန်ပစ္စည်းများ',
      'Incoming Products': 'ဝင်လာသော ကုန်ပစ္စည်းများ',
      'Sale': 'အရောင်း',
      'Customer': 'ဖောက်သည်',
      'Customers': 'ဖောက်သည်များ',
      'Supplier': 'ပစ္စည်းပေးသွင်းသူ',
      'Suppliers': 'ပစ္စည်းပေးသွင်းသူများ',
      'Vouchers': 'ဘောင်ချာများ',
      'Income/Expense': 'ဝင်ငွေ/အသုံးစရိတ်',
      'Sales Report': 'အရောင်းအစီရင်ခံစာ',
      'Cylinder Cycles': 'ဓာတ်ငွေ့အိုး အဝင်အထွက်မှတ်တမ်း',
      'Cylinder Types': 'ဓာတ်ငွေ့အိုး အမျိုးအစားများ',
      'Welcome from ': 'ကြိုဆိုပါသည် — ',
      'Kyal Sin Lay Energy & Tech Point of Sale System': 'Kyal Sin Lay Energy & Tech အရောင်းဆိုင် စီမံခန့်ခွဲမှုစနစ်',
      'Cancel': 'ပယ်ဖျက်ရန်',
      'Save': 'သိမ်းရန်',
      'OK': 'အိုကေ',
      'Select': 'ရွေးရန်',
      'Close': 'ပိတ်ရန်',
      'Delete': 'ဖျက်ရန်',
      'Remove': 'ဖယ်ရှားရန်',
      'View': 'ကြည့်ရန်',
      'Edit': 'တည်းဖြတ်ရန်',
      'Import': 'ထည့်သွင်းရန်',
      'Export': 'ထုတ်ယူရန်',
      'Erase': 'ဖျက်ပစ်ရန်',
      'Add': 'ထည့်ရန်',
      'Pay': 'ပေးရန်',
      'Receive': 'လက်ခံရန်',
      'Copy Details': 'အသေးစိတ်ကို ကူးယူရန်',
      'Save Voucher': 'ဘောင်ချာသိမ်းရန်',
      'Share as image': 'ပုံအဖြစ် မျှဝေရန်',
      'Save as photo': 'ဓာတ်ပုံအဖြစ် သိမ်းရန်',
      'Edit voucher': 'ဘောင်ချာတည်းဖြတ်ရန်',
      'Delete voucher': 'ဘောင်ချာဖျက်ရန်',
      'Delete voucher?': 'ဘောင်ချာဖျက်မည်လား?',
      'Delete product': 'ကုန်ပစ္စည်းဖျက်ရန်',
      'Delete product?': 'ကုန်ပစ္စည်းဖျက်မည်လား?',
      'Remove product?': 'ကုန်ပစ္စည်းဖယ်ရှားမည်လား?',
      'Delete incoming record': 'ဝင်ကုန်မှတ်တမ်းဖျက်ရန်',
      'Delete incoming record?': 'ဝင်ကုန်မှတ်တမ်းဖျက်မည်လား?',
      'Delete cylinder type?': 'ဓာတ်ငွေ့အိုးအမျိုးအစား ဖျက်မည်လား?',
      'Delete history record?': 'မှတ်တမ်းဖျက်မည်လား?',
      'Delete this history': 'ဤမှတ်တမ်းကို ဖျက်ရန်',
      'Delete this record': 'ဤမှတ်တမ်းကို ဖျက်ရန်',
      'Delete history': 'မှတ်တမ်းဖျက်ရန်',
      'View all history': 'မှတ်တမ်းအားလုံးကြည့်ရန်',
      'Payment amount': 'ပေးချေငွေပမာဏ',
      'Payment method': 'ပေးချေနည်းလမ်း',
      'Payment date ': 'ပေးချေသည့်ရက် ',
      'Cash': 'ငွေသား',
      'Bank': 'ဘဏ်',
      'Mobile': 'မိုဘိုင်းငွေပေးချေမှု',
      'Credit': 'အကြွေး',
      'Save payment': 'ပေးချေမှုသိမ်းရန်',
      'Payment history': 'ပေးချေမှုမှတ်တမ်း',
      'Payment History': 'ပေးချေမှုမှတ်တမ်း',
      'Amount paid (total ': 'ပေးထားသောငွေ (စုစုပေါင်း ',
      'Amount Paid (MMK)': 'ပေးထားသောငွေ (MMK)',
      'Amount paid to supplier': 'ပစ္စည်းပေးသွင်းသူထံ ပေးထားသောငွေ',
      'Payment Method': 'ပေးချေနည်းလမ်း',
      'Paid': 'ပေးပြီး',
      'Received': 'လက်ခံရရှိ',
      'Adjustment': 'ပြင်ဆင်ငွေ',
      'Balance': 'လက်ကျန်',
      'Outstanding': 'ကျန်ငွေ',
      'PARTIALLY PAID': 'တစ်စိတ်တစ်ပိုင်း ပေးပြီး',
      'PAID': 'ပေးပြီး',
      'UNPAID': 'မပေးရသေး',
      'Select transaction date': 'အရောင်းအဝယ်ရက် ရွေးရန်',
      'Select entry date': 'စာရင်းသွင်းရက် ရွေးရန်',
      'Select report date': 'အစီရင်ခံစာရက် ရွေးရန်',
      'Select Month': 'လ ရွေးရန်',
      'Select Year': 'နှစ် ရွေးရန်',
      'Select Date': 'ရက်စွဲ ရွေးရန်',
      'Date': 'ရက်စွဲ',
      'Year': 'နှစ်',
      'Daily': 'နေ့စဉ်',
      'Monthly': 'လစဉ်',
      'Yearly': 'နှစ်စဉ်',
      'Previous period': 'ယခင်ကာလ',
      'Next period': 'နောက်ကာလ',
      'Today': 'ယနေ့',
      'January': 'ဇန်နဝါရီ',
      'February': 'ဖေဖော်ဝါရီ',
      'March': 'မတ်',
      'April': 'ဧပြီ',
      'May': 'မေ',
      'June': 'ဇွန်',
      'July': 'ဇူလိုင်',
      'August': 'ဩဂုတ်',
      'September': 'စက်တင်ဘာ',
      'October': 'အောက်တိုဘာ',
      'November': 'နိုဝင်ဘာ',
      'December': 'ဒီဇင်ဘာ',
      'Add Entry': 'စာရင်းထည့်ရန်',
      'Income': 'ဝင်ငွေ',
      'Expense': 'အသုံးစရိတ်',
      'Description': 'ဖော်ပြချက်',
      'Amount': 'ပမာဏ',
      'Note (optional)': 'မှတ်ချက် (မဖြည့်လည်းရ)',
      'Summary': 'အနှစ်ချုပ်',
      'Linked payment transaction': 'ချိတ်ဆက်ထားသော ပေးချေမှုအရောင်းအဝယ်',
      'Transactions': 'အရောင်းအဝယ်များ',
      'Profit before expenses': 'အသုံးစရိတ်မနှုတ်မီ အမြတ်',
      'Profit after expenses': 'အသုံးစရိတ်နုတ်ပြီး အမြတ်',
      'No transactions for this period.': 'ဤကာလအတွင်း အရောင်းအဝယ်မရှိပါ။',
      'No sales recorded for this period.': 'ဤကာလအတွင်း အရောင်းမှတ်တမ်းမရှိပါ။',
      'Automatically generated': 'အလိုအလျောက် ဖန်တီးထားသည်',
      'Generate PDF report': 'PDF အစီရင်ခံစာ ဖန်တီးရန်',
      'PDF Report': 'PDF အစီရင်ခံစာ',
      'Add New Product': 'ကုန်ပစ္စည်းအသစ် ထည့်ရန်',
      'Edit Product': 'ကုန်ပစ္စည်းတည်းဖြတ်ရန်',
      'Product Catalog': 'ကုန်ပစ္စည်းစာရင်း',
      'Product name *': 'ကုန်ပစ္စည်းအမည် *',
      'Product': 'ကုန်ပစ္စည်း',
      'Type': 'အမျိုးအစား',
      'Variant / sub type': 'မျိုးကွဲ / အခွဲအမျိုးအစား',
      'Sub Type': 'အခွဲအမျိုးအစား',
      'Selling price': 'ရောင်းဈေး',
      'Selling price 2': 'ရောင်းဈေး ၂',
      'Selling price 3': 'ရောင်းဈေး ၃',
      'Cost per sale unit': 'တစ်ရောင်းယူနစ်အတွက် ကုန်ကျစရိတ်',
      'Cost': 'ကုန်ကျစရိတ်',
      'Optional': 'မဖြည့်လည်းရ',
      'This is a selling variant': 'ဤသည်မှာ ရောင်းချရန် မျိုးကွဲဖြစ်သည်',
      'Main stock product': 'အဓိက လက်ကျန်ကုန်ပစ္စည်း',
      'How is this variant sold?': 'ဤမျိုးကွဲကို မည်သို့ရောင်းမည်နည်း?',
      'By a fixed unit': 'သတ်မှတ်ယူနစ်ဖြင့်',
      'By kg or viss at sale': 'ရောင်းချချိန်တွင် ကီလို သို့မဟုတ် ပိဿာဖြင့်',
      'Advanced inventory settings': 'အဆင့်မြင့် လက်ကျန်စီမံမှု ဆက်တင်များ',
      'Usually leave these alone': 'ပုံမှန်အားဖြင့် မပြင်ဘဲထားပါ',
      'Stock unit': 'လက်ကျန်ယူနစ်',
      'Incoming unit': 'ဝင်ယူနစ်',
      'Sale unit': 'ရောင်းယူနစ်',
      'Incoming conversion': 'ဝင်ယူနစ်မှ လက်ကျန်သို့ ပြောင်းနှုန်း',
      'Sale conversion': 'ရောင်းယူနစ်မှ လက်ကျန်အသုံးပြုမှု ပြောင်းနှုန်း',
      'Additional selling prices': 'ထပ်ဆောင်း ရောင်းဈေးများ',
      'Default / preferred supplier': 'ပုံမှန် / နှစ်သက်ရာ ပစ္စည်းပေးသွင်းသူ',
      'No supplier selected': 'ပစ္စည်းပေးသွင်းသူ မရွေးရသေးပါ',
      'Create Product': 'ကုန်ပစ္စည်း ဖန်တီးရန်',
      'Save Changes': 'ပြင်ဆင်ချက်များ သိမ်းရန်',
      'Edit product': 'ကုန်ပစ္စည်းတည်းဖြတ်ရန်',
      'Qty': 'အရေအတွက်',
      'Unit': 'ယူနစ်',
      'Price 1': 'ဈေး ၁',
      'Last Incoming': 'နောက်ဆုံး ဝင်ကုန်',
      'Search product': 'ကုန်ပစ္စည်းရှာရန်',
      'Record Incoming Stock': 'ဝင်ကုန်လက်ကျန် မှတ်တမ်းတင်ရန်',
      'Select Main Stock Product': 'အဓိက လက်ကျန်ကုန်ပစ္စည်း ရွေးရန်',
      'No main stock products created yet': 'အဓိက လက်ကျန်ကုန်ပစ္စည်း မဖန်တီးရသေးပါ',
      'Current stock': 'လက်ရှိလက်ကျန်',
      'Incoming quantity': 'ဝင်ကုန်အရေအတွက်',
      'Stock added': 'ထပ်တိုးလက်ကျန်',
      'Cost per ': 'တစ်ခုလျှင် ကုန်ကျစရိတ် ',
      'Incoming date': 'ဝင်ကုန်ရက်',
      'Add Incoming Stock': 'ဝင်ကုန်လက်ကျန် ထည့်ရန်',
      'Incoming History': 'ဝင်ကုန်မှတ်တမ်း',
      'No incoming stock transactions yet.': 'ဝင်ကုန်လက်ကျန် အရောင်းအဝယ်မှတ်တမ်း မရှိသေးပါ။',
      'Balance MMK': 'လက်ကျန် MMK',
      'stock units': 'လက်ကျန်ယူနစ်များ',
      'stock unit(s)': 'လက်ကျန်ယူနစ်',
      'People': 'လူစာရင်း',
      'Category': 'အမျိုးအစား',
      'Entity or Person name': 'လုပ်ငန်း/လူအမည်',
      'Phone number': 'ဖုန်းနံပါတ်',
      'Address': 'လိပ်စာ',
      'Add ': 'ထည့်ရန် ',
      'Please enter a name': 'အမည်ထည့်ပါ',
      'Sale Page': 'အရောင်းစာမျက်နှာ',
      'Voucher Details': 'ဘောင်ချာအသေးစိတ်',
      'Select Registered Customer': 'စာရင်းသွင်းထားသော ဖောက်သည်ကို ရွေးရန်',
      'Customer Name (Manual Entry / Selected)': 'ဖောက်သည်အမည် (ကိုယ်တိုင်ထည့် / ရွေးထား)',
      'Product Type': 'ကုန်ပစ္စည်းအမျိုးအစား',
      'All Types': 'အမျိုးအစားအားလုံး',
      'All SubTypes': 'အခွဲအမျိုးအစားအားလုံး',
      'Select Product': 'ကုန်ပစ္စည်း ရွေးရန်',
      'Legacy loose-gas sale unit': 'ယခင် loose-gas ရောင်းယူနစ်',
      'Kg': 'ကီလို',
      'Viss': 'ပိဿာ',
      'Select Price': 'ဈေးနှုန်း ရွေးရန်',
      'Quantity': 'အရေအတွက်',
      'Add Item to Voucher': 'ဘောင်ချာထဲသို့ ပစ္စည်းထည့်ရန်',
      'Added Items:': 'ထည့်ထားသော ပစ္စည်းများ:',
      'Grand Total: MMK ': 'စုစုပေါင်း: MMK ',
      'Balance: MMK ': 'လက်ကျန်: MMK ',
      'VOUCHER': 'ဘောင်ချာ',
      'Prepared For: ': 'အတွက် ပြင်ဆင်ထားသည်: ',
      'Price': 'ဈေးနှုန်း',
      'No': 'အမှတ်',
      'Items': 'ပစ္စည်းများ',
      'Status': 'အခြေအနေ',
      'Total': 'စုစုပေါင်း',
      'Total Left': 'ကျန်ငွေစုစုပေါင်း',
      'Customer Sign': 'ဖောက်သည် လက်မှတ်',
      'Seller Sign': 'ရောင်းချသူ လက်မှတ်',
      'Sales Detail': 'အရောင်းအသေးစိတ်',
      'Sales Detail (continued)': 'အရောင်းအသေးစိတ် (ဆက်လက်)',
      'Yearly Sales Summary': 'နှစ်စဉ်အရောင်း အနှစ်ချုပ်',
      'Sales Count': 'အရောင်းအကြိမ်ရေ',
      'Sales': 'အရောင်း',
      'Expenses': 'အသုံးစရိတ်များ',
      'Net': 'အသားတင်',
      'YEAR TOTAL': 'နှစ်စုစုပေါင်း',
      'Voucher No.': 'ဘောင်ချာအမှတ်',
      'Profit': 'အမြတ်',
      'LPG Cost': 'LPG ကုန်ကျစရိတ်',
      'Total Sales': 'စုစုပေါင်းအရောင်း',
      'Profit Before Expenses': 'အသုံးစရိတ်မနှုတ်မီ အမြတ်',
      'Profit After Expenses': 'အသုံးစရိတ်နုတ်ပြီး အမြတ်',
      'Generated: ': 'ဖန်တီးသည့်ရက်: ',
      'Page ': 'စာမျက်နှာ ',
      'PDF generation failed:': 'PDF ဖန်တီးမှု မအောင်မြင်ပါ:',
      'Sales report': 'အရောင်းအစီရင်ခံစာ',
      'Add Type': 'အမျိုးအစားထည့်ရန်',
      'Add Cylinder Type': 'ဓာတ်ငွေ့အိုး အမျိုးအစားထည့်ရန်',
      'Cylinder category': 'ဓာတ်ငွေ့အိုး အမျိုးအစား',
      'Name of type': 'အမျိုးအစားအမည်',
      'Opening cylinder stock': 'အစဖွင့် ဓာတ်ငွေ့အိုးလက်ကျန်',
      'Set current quantity': 'လက်ရှိအရေအတွက် သတ်မှတ်ရန်',
      'Currently in our possession': 'လက်ရှိ ကျွန်ုပ်တို့ထံရှိသည်',
      'In our possession': 'ကျွန်ုပ်တို့ထံရှိသည်',
      'History': 'မှတ်တမ်း',
      'New Cylinder Cycle': 'ဓာတ်ငွေ့အိုး အဝင်အထွက်အသစ်',
      'Cylinder Type': 'ဓာတ်ငွေ့အိုး အမျိုးအစား',
      'How much we give': 'ပေးလိုက်သည့်အရေအတွက်',
      'How much we get': 'ရရှိသည့်အရေအတွက်',
      'Cycle date: ': 'အဝင်အထွက်ရက်: ',
      'Save Cylinder Cycle': 'ဓာတ်ငွေ့အိုး အဝင်အထွက် သိမ်းရန်',
      'Customer Cylinders': 'ဖောက်သည်ထံရှိ ဓာတ်ငွေ့အိုးများ',
      'All customers are listed here. Open a customer to see the exact cylinder types, balances, and transaction history.': 'ဖောက်သည်အားလုံးကို ဤနေရာတွင် ဖော်ပြထားပါသည်။ ဖောက်သည်တစ်ဦးကို ဖွင့်ကြည့်ပါက ဓာတ်ငွေ့အိုးအမျိုးအစားအလိုက် အတိအကျ အရေအတွက်၊ လက်ကျန်နှင့် အရောင်းအဝယ်မှတ်တမ်းများကို ကြည့်နိုင်ပါသည်။',
      'Total cylinders: {qty}': 'ဓာတ်ငွေ့အိုး စုစုပေါင်း: {qty}',
      'No cylinder activity': 'ဓာတ်ငွေ့အိုး အဝင်အထွက်မှတ်တမ်း မရှိပါ',
      'No customers added yet.': 'ဖောက်သည် မထည့်ရသေးပါ။',
      'Add customers first, then their cylinder balances will appear here.': 'ဖောက်သည်များကို အရင်ထည့်ပါ။ ထို့နောက် ၎င်းတို့၏ ဓာတ်ငွေ့အိုးလက်ကျန်များကို ဤနေရာတွင် ပြသပါမည်။',
      'Cylinder Type Breakdown': 'ဓာတ်ငွေ့အိုးအမျိုးအစားအလိုက် အသေးစိတ်',
      'No cylinder activity recorded for this customer.': 'ဤဖောက်သည်အတွက် ဓာတ်ငွေ့အိုး အဝင်အထွက်မှတ်တမ်း မရှိပါ။',
      'With customer': 'ဖောက်သည်ထံတွင်',
      'With us': 'ကျွန်ုပ်တို့ထံတွင်',
      'with customer': 'ဖောက်သည်ထံတွင်',
      'with us': 'ကျွန်ုပ်တို့ထံတွင်',
      'settled': 'ရှင်းပြီး',
      'No transactions recorded for this customer.': 'ဤဖောက်သည်အတွက် အရောင်းအဝယ်မှတ်တမ်း မရှိပါ။',
      'Delete this transaction': 'ဤအရောင်းအဝယ်ကို ဖျက်ရန်',
      'Outstanding Customer Cylinders': 'ဖောက်သည်ထံကျန်နေသော ဓာတ်ငွေ့အိုးများ',
      'Cylinder Stock': 'ဓာတ်ငွေ့အိုးလက်ကျန်',
      'We have': 'ကျွန်ုပ်တို့ထံရှိသည်',
      'Everything is settled': 'အားလုံး ရှင်းပြီးပါပြီ',
      'Settled': 'ရှင်းပြီး',
      'Active ': 'လက်ရှိ ',
      'Customer owes us': 'ဖောက်သည်က ကျွန်ုပ်တို့ကို ပေးရန်ရှိသည်',
      'We owe customer': 'ကျွန်ုပ်တို့က ဖောက်သည်ကို ပေးရန်ရှိသည်',
      'Replace all data?': 'ဒေတာအားလုံးကို အစားထိုးမည်လား?',
      'Import Backup File': 'အရန်ဒေတာဖိုင် ထည့်သွင်းရန်',
      'Import from Clipboard': 'Clipboard မှ ထည့်သွင်းရန်',
      'Import Pasted Backup': 'ကူးထည့်ထားသော အရန်ဒေတာကို ထည့်သွင်းရန်',
      'Importing...': 'ထည့်သွင်းနေသည်...',
      'Save Backup File': 'အရန်ဒေတာဖိုင် သိမ်းရန်',
      'Copy Backup to Clipboard': 'အရန်ဒေတာကို Clipboard သို့ ကူးယူရန်',
      'Paste a smaller backup JSON here': 'အသေးစား အရန် JSON ကို ဤနေရာတွင် ကူးထည့်ပါ',
      'Danger zone': 'သတိထားရန် ဧရိယာ',
      'Erase All Data': 'ဒေတာအားလုံး ဖျက်ပစ်ရန်',
      'Backup is empty.': 'အရန်ဒေတာအလွတ်ဖြစ်နေပါသည်။',
      'The backup is empty.': 'အရန်ဒေတာအလွတ်ဖြစ်နေပါသည်။',
      'Save failed. Your last saved data was kept.': 'သိမ်းဆည်းမှု မအောင်မြင်ပါ။ နောက်ဆုံးသိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Could not save data: ': 'ဒေတာသိမ်းဆည်း၍ မရပါ: ',
      'Data could not be saved. Your previous saved data was kept.': 'ဒေတာသိမ်းဆည်း၍ မရပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Data imported successfully': 'ဒေတာ အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ',
      'Import failed: ': 'ထည့်သွင်းမှု မအောင်မြင်ပါ: ',
      'Could not import the backup file: ': 'အရန်ဒေတာဖိုင် ထည့်သွင်း၍ မရပါ: ',
      'Clipboard import failed: ': 'Clipboard မှ ထည့်သွင်းမှု မအောင်မြင်ပါ: ',
      'Erase all data?': 'ဒေတာအားလုံး ဖျက်ပစ်မည်လား?',
      'All data erased': 'ဒေတာအားလုံး ဖျက်ပစ်ပြီးပါပြီ',
      'Data loaded, but the migration could not be saved.': 'ဒေတာဖတ်ပြီးပါပြီ၊ သို့သော် ပြောင်းရွှေ့ပြင်ဆင်မှုကို မသိမ်းနိုင်ပါ။',
      'Stored data could not be loaded safely: ': 'သိမ်းထားသောဒေတာကို လုံခြုံစွာ ဖတ်မရပါ: ',
      'Product name cannot be empty.': 'ကုန်ပစ္စည်းအမည် မဖြစ်မနေထည့်ရပါမည်။',
      'Product was not found.': 'ကုန်ပစ္စည်း မတွေ့ပါ။',
      'Incoming quantity must be greater than zero.': 'ဝင်ကုန်အရေအတွက်သည် သုညထက် ကြီးရပါမည်။',
      'Incoming cost cannot be negative.': 'ဝင်ကုန်ကုန်ကျစရိတ်သည် အနုတ်မဖြစ်ရပါ။',
      'Cost cannot be negative.': 'ကုန်ကျစရိတ်သည် အနုတ်မဖြစ်ရပါ။',
      'Paid amount must be between 0 and the incoming total.': 'ပေးချေငွေသည် ၀ နှင့် ဝင်ကုန်စုစုပေါင်းအကြား ဖြစ်ရပါမည်။',
      'Please select an existing main stock product first.': 'ရှိပြီးသား အဓိကလက်ကျန်ကုန်ပစ္စည်းကို အရင်ရွေးပါ။',
      'Selling variants cannot receive stock directly.': 'ရောင်းရန်မျိုးကွဲများထဲသို့ လက်ကျန်ကို တိုက်ရိုက်ထည့်၍မရပါ။',
      'Please enter a product name.': 'ကုန်ပစ္စည်းအမည်ထည့်ပါ။',
      'Please enter a cylinder type name.': 'ဓာတ်ငွေ့အိုးအမျိုးအစားအမည်ထည့်ပါ။',
      'Cylinder stock must be 0 or more.': 'ဓာတ်ငွေ့အိုးလက်ကျန်သည် ၀ သို့မဟုတ် ထို့ထက်များရပါမည်။',
      'Cylinder quantities must be 0 or more.': 'ဓာတ်ငွေ့အိုးအရေအတွက်သည် ၀ သို့မဟုတ် ထို့ထက်များရပါမည်။',
      'Please select a customer': 'ဖောက်သည်ကို ရွေးပါ',
      'Please add and select a cylinder type': 'ဓာတ်ငွေ့အိုးအမျိုးအစားကို ထည့်ပြီး ရွေးပါ',
      'Enter how much we give or receive': 'ပေးမည်/ရမည် အရေအတွက်ကို ထည့်ပါ',
      'Enter a description and a valid amount': 'ဖော်ပြချက်နှင့် မှန်ကန်သော ပမာဏကို ထည့်ပါ',
      'Enter a name and a valid amount': 'အမည်နှင့် မှန်ကန်သော ပမာဏကို ထည့်ပါ',
      'Select a product, sale unit, price, and a valid quantity.': 'ကုန်ပစ္စည်း၊ ရောင်းယူနစ်၊ ဈေးနှုန်းနှင့် မှန်ကန်သော အရေအတွက်ကို ရွေးပါ။',
      'Select a valid LPG sale unit.': 'မှန်ကန်သော LPG ရောင်းယူနစ်ကို ရွေးပါ။',
      'Add at least one item before saving the voucher': 'ဘောင်ချာမသိမ်းမီ အနည်းဆုံး ပစ္စည်းတစ်ခု ထည့်ပါ',
      'Could not save voucher: ': 'ဘောင်ချာသိမ်း၍ မရပါ: ',
      'Voucher saved successfully. Cha-ching!': 'ဘောင်ချာကို အောင်မြင်စွာ သိမ်းပြီးပါပြီ။ ချင့်!',
      'Voucher details copied to clipboard': 'ဘောင်ချာအသေးစိတ်ကို Clipboard သို့ ကူးယူပြီးပါပြီ',
      'Could not share the voucher: ': 'ဘောင်ချာမျှဝေ၍ မရပါ: ',
      'Could not save the voucher: ': 'ဘောင်ချာသိမ်း၍ မရပါ: ',
      'Could not generate the PDF report: ': 'PDF အစီရင်ခံစာ ဖန်တီး၍ မရပါ: ',
      'Yearly report saved to ': 'နှစ်စဉ်အစီရင်ခံစာကို သိမ်းပြီးပါပြီ: ',
      'Cannot be undone.': 'ပြန်လည်ပြင်ဆင်၍ မရပါ။',
      'Nothing to pay. All supplier balances are settled.': 'ပေးရန်မရှိတော့ပါ။ ပစ္စည်းပေးသွင်းသူ လက်ကျန်အားလုံး ရှင်းပြီးပါပြီ။',
      'Nothing to receive. All customer balances are settled.': 'ရရန်မရှိတော့ပါ။ ဖောက်သည် လက်ကျန်အားလုံး ရှင်းပြီးပါပြီ။',
      'No payment transactions recorded.': 'ပေးချေမှုအရောင်းအဝယ်မှတ်တမ်း မရှိပါ။',
      'No products yet. Create a product above first.': 'ကုန်ပစ္စည်းမရှိသေးပါ။ အပေါ်တွင် ကုန်ပစ္စည်းတစ်ခုကို အရင်ဖန်တီးပါ။',
      'No vouchers saved yet. Create one from the Sale page.': 'သိမ်းထားသော ဘောင်ချာမရှိသေးပါ။ အရောင်းစာမျက်နှာမှ တစ်ခုဖန်တီးပါ။',
      'No history recorded for this customer.': 'ဤဖောက်သည်အတွက် မှတ်တမ်းမရှိပါ။',
      'No history recorded for this type.': 'ဤအမျိုးအစားအတွက် မှတ်တမ်းမရှိပါ။',
      'No cylinder types have been added.': 'ဓာတ်ငွေ့အိုးအမျိုးအစား မထည့်ရသေးပါ။',
      'There is no history to delete for ': 'ဖျက်ရန် မှတ်တမ်းမရှိပါ: ',
      'All history for this type has been deleted.': 'ဤအမျိုးအစား၏ မှတ်တမ်းအားလုံးကို ဖျက်ပြီးပါပြီ။',
      'No customer currently has an outstanding cylinder balance.': 'လက်ရှိတွင် ဖောက်သည်ထံ ကျန်နေသော ဓာတ်ငွေ့အိုးလက်ကျန် မရှိပါ။',
      'Example: LPG Kg': 'ဥပမာ - LPG Kg',
      'Example: LPG': 'ဥပမာ - LPG',
      'Example: 220g, Viss, Kg': 'ဥပမာ - 220g, Viss, Kg',
      'Enter the essentials. Inventory rules are filled automatically for common products.': 'အခြေခံအချက်များကို ထည့်ပါ။ ပုံမှန်ကုန်ပစ္စည်းများအတွက် လက်ကျန်စီမံမှုစည်းမျဉ်းများကို အလိုအလျောက် ဖြည့်ပေးပါမည်။',
      'Turn this on when the product uses stock from another product, such as LPG 220g or LPG Viss.': 'LPG 220g သို့မဟုတ် LPG Viss ကဲ့သို့ အခြားကုန်ပစ္စည်း၏ လက်ကျန်ကို အသုံးပြုပါက ဤရွေးချယ်မှုကို ဖွင့်ပါ။',
      'Create a main stock product first': 'အဓိကလက်ကျန်ကုန်ပစ္စည်းကို အရင်ဖန်တီးပါ',
      'Choose the product whose stock this variant uses': 'ဤမျိုးကွဲက အသုံးပြုမည့် လက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ',
      'These values are stored for the inventory engine. Most products can use the automatic defaults.': 'ဤတန်ဖိုးများကို လက်ကျန်စီမံမှုအင်ဂျင်အတွက် သိမ်းထားပါသည်။ ကုန်ပစ္စည်းအများစုသည် အလိုအလျောက်သတ်မှတ်ချက်များကို အသုံးပြုနိုင်ပါသည်။',
      'What you buy/receive': 'သင် ဝယ်ယူ/လက်ခံသည့်အရာ',
      'What you sell': 'သင် ရောင်းချသည့်အရာ',
      'How incoming units become stock': 'ဝင်ယူနစ်များသည် လက်ကျန်အဖြစ် မည်သို့ပြောင်းမည်နည်း',
      'Enter the cylinders you currently have. This is the stock starting balance.': 'လက်ရှိသင့်ထံရှိ ဓာတ်ငွေ့အိုးအရေအတွက်ကို ထည့်ပါ။ ဤသည်မှာ စတင်လက်ကျန်ဖြစ်သည်။',
      '1 kg → 1 kg (fixed)': '1 ကီလို → 1 ကီလို (သတ်မှတ်ထားသည်)',
      '220g → 0.22 kg': '220g → 0.22 ကီလို',
      'kg (fixed for LPG)': 'ကီလို (LPG အတွက် သတ်မှတ်ထားသည်)',
      'unit, kg, piece, box': 'ယူနစ်၊ ကီလို၊ ခု၊ ဘူး',
      '10v': '10 ပိဿာ',
      '48kg': '48 ကီလို',
      '48 kg': '48 ကီလို',
      'Viss (1 viss = 1.6 kg)': 'ပိဿာ (1 ပိဿာ = 1.6 ကီလို)',
      'e.g. Standard 48 kg, Small 10v': 'ဥပမာ - Standard 48 kg၊ Small 10v',
      'Voucher': 'ဘောင်ချာ',
      'Add cylinder types first.': 'ဓာတ်ငွေ့အိုးအမျိုးအစားကို အရင်ထည့်ပါ။',
      'Cylinder cycle saved': 'ဓာတ်ငွေ့အိုး အဝင်အထွက်ကို သိမ်းပြီးပါပြီ',
      'Enter an amount within the outstanding balance.': 'ကျန်ငွေပမာဏအတွင်းမှ ငွေပမာဏတစ်ခု ထည့်ပါ။',
      'Enter how much parent stock one sale unit consumes.': 'ရောင်းယူနစ်တစ်ခုအတွက် အဓိကလက်ကျန်မှ မည်မျှအသုံးပြုမည်ကို ထည့်ပါ။',
      'Incoming amount must be greater than zero.': 'ဝင်ကုန်ပမာဏသည် သုညထက် ကြီးရပါမည်။',
      'Incoming record deleted and stock reversed.': 'ဝင်ကုန်မှတ်တမ်းကို ဖျက်ပြီး လက်ကျန်ကို မူလအတိုင်း ပြန်လည်ပြင်ဆင်ပြီးပါပြီ။',
      'Incoming stock conversion must be greater than zero.': 'ဝင်ကုန်လက်ကျန် ပြောင်းနှုန်းသည် သုညထက် ကြီးရပါမည်။',
      'No products yet. Add a master product from Products, then add stock through Incoming Products.': 'ကုန်ပစ္စည်းမရှိသေးပါ။ Products မှ အဓိကကုန်ပစ္စည်းတစ်ခုထည့်ပြီး Incoming Products မှ လက်ကျန်ထည့်ပါ။',
      'Product created.': 'ကုန်ပစ္စည်း ဖန်တီးပြီးပါပြီ။',
      'Product deleted.': 'ကုန်ပစ္စည်း ဖျက်ပြီးပါပြီ။',
      'Product updated.': 'ကုန်ပစ္စည်း ပြင်ဆင်ပြီးပါပြီ။',
      'Select the main stock product for this selling variant.': 'ဤရောင်းရန်မျိုးကွဲအတွက် အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ။',
      'Stock used per direct sale unit must be greater than zero.': 'တိုက်ရိုက်ရောင်းယူနစ်တစ်ခုအတွက် အသုံးပြုသည့် လက်ကျန်သည် သုညထက် ကြီးရပါမည်။',
      'Period: ': 'ကာလ: ',
      'Transactions: ': 'အရောင်းအဝယ်: ',
      'Sales • ': 'အရောင်း • ',
      'Yearly export uses a compact monthly summary to avoid excessive memory use on large transaction histories.': 'အရောင်းအဝယ်မှတ်တမ်းများ များပြားသောအခါ မှတ်ဉာဏ်အသုံးပြုမှုလျှော့ချရန် နှစ်စဉ်ထုတ်ယူမှုတွင် လစဉ်အနှစ်ချုပ်ပုံစံကို အသုံးပြုထားပါသည်။',
      'Save Yearly Sales Report': 'နှစ်စဉ်အရောင်းအစီရင်ခံစာ သိမ်းရန်',
      'Yearly Sales Summary - ': 'နှစ်စဉ်အရောင်းအနှစ်ချုပ် - ',
      'Name: ': 'အမည်: ',
      'Items: ': 'ပစ္စည်းများ: ',
      'Total: ': 'စုစုပေါင်း: ',
      'Date: ': 'ရက်စွဲ: ',
      'Paid: ': 'ပေးပြီး: ',
      'Profit ': 'အမြတ် ',
      'Report': 'အစီရင်ခံစာ',
      'Month': 'လ',
      'Save a complete snapshot of your data as a JSON backup. This is the recommended method for large backups because it does not depend on clipboard limits.': 'သင့်ဒေတာအားလုံးကို JSON အရန်ဒေတာအဖြစ် သိမ်းပါ။ Clipboard ကန့်သတ်ချက်များနှင့် မသက်ဆိုင်သောကြောင့် ဒေတာအများအပြားအတွက် ဤနည်းလမ်းကို အကြံပြုပါသည်။',
      'For large backups, import the original .json/.txt file directly. This bypasses clipboard and text-box size limits. You can still paste smaller backups below.': 'ဒေတာအများအပြားအတွက် မူရင်း .json/.txt ဖိုင်ကို တိုက်ရိုက်ထည့်သွင်းပါ။ ထိုနည်းဖြင့် Clipboard နှင့် စာသားအကွက်အရွယ်အစား ကန့်သတ်ချက်များကို ကျော်လွှားနိုင်ပါသည်။ အသေးစားအရန်ဒေတာများကို အောက်တွင် ဆက်လက်ကူးထည့်နိုင်ပါသည်။',
      'Backup copied': 'အရန်ဒေတာ ကူးယူပြီးပါပြီ',
      'Backup file saved': 'အရန်ဒေတာဖိုင် သိမ်းပြီးပါပြီ',
      'Pay Yan comes from unpaid IncomingSupply records. Record the supplier purchase first; it will appear here automatically.': 'ပေးရန်စာရင်းသည် မပေးရသေးသော ဝင်ကုန်မှတ်တမ်းများမှ အလိုအလျောက် ရရှိပါသည်။ ပစ္စည်းပေးသွင်းသူထံမှ ဝယ်ယူမှုကို အရင်မှတ်တမ်းတင်ပါ။ ထို့နောက် ဤနေရာတွင် အလိုအလျောက် ပေါ်လာပါမည်။',
      'Ya Yan comes from unpaid Sale records. Record the sale and payment first; it will appear here automatically.': 'ရရန်စာရင်းသည် မရသေးသော အရောင်းမှတ်တမ်းများမှ အလိုအလျောက် ရရှိပါသည်။ အရောင်းနှင့် ငွေပေးချေမှုကို အရင်မှတ်တမ်းတင်ပါ။ ထို့နောက် ဤနေရာတွင် အလိုအလျောက် ပေါ်လာပါမည်။',
      'Pay Yan entries come from IncomingSupply. Update the purchase payment instead.': 'ပေးရန်စာရင်းသည် ဝင်ကုန်မှတ်တမ်းများမှ ရရှိပါသည်။ ဝယ်ယူမှု၏ ပေးချေမှုကိုသာ ပြင်ဆင်ပါ။',
      'Ya Yan entries come from Sale. Update the sale payment instead.': 'ရရန်စာရင်းသည် အရောင်းမှတ်တမ်းများမှ ရရှိပါသည်။ အရောင်း၏ ပေးချေမှုကိုသာ ပြင်ဆင်ပါ။',
      'There is no text backup in the clipboard.': 'Clipboard ထဲတွင် အရန်စာသားဒေတာ မရှိပါ။',
      'Could not save the backup file: ': 'အရန်ဒေတာဖိုင် သိမ်း၍ မရပါ: ',
      'Could not capture the voucher image.': 'ဘောင်ချာပုံကို ဖမ်းယူ၍ မရပါ။',
      'Sharing isn\'t supported on this device — the voucher image was saved instead.': 'ဤစက်တွင် မျှဝေမှုကို မပံ့ပိုးပါ။ ဘောင်ချာပုံကို အစား သိမ်းဆည်းထားပါသည်။',
      'Voucher image saved to your gallery': 'ဘောင်ချာပုံကို Gallery ထဲသို့ သိမ်းပြီးပါပြီ',
      'Voucher image saved': 'ဘောင်ချာပုံကို သိမ်းပြီးပါပြီ',
      'The backup is ': 'အရန်ဒေတာသည် ',
      'This backup is ': 'ဤအရန်ဒေတာသည် ',
      'Importing it will overwrite everything currently stored on this device.': '၎င်းကို ထည့်သွင်းပါက ဤစက်တွင် လက်ရှိသိမ်းထားသမျှ အားလုံးကို အစားထိုးသွားပါမည်။',
      'This deletes every product, person, voucher, and ledger entry on this device. This cannot be undone.': 'ဤလုပ်ဆောင်ချက်သည် ဤစက်ရှိ ကုန်ပစ္စည်း၊ လူစာရင်း၊ ဘောင်ချာနှင့် စာရင်းမှတ်တမ်းအားလုံးကို ဖျက်ပစ်ပါမည်။ ပြန်လည်ပြင်ဆင်၍ မရပါ။',
      'Add suppliers from the Suppliers page to use named supplier records in incoming stock.': 'ဝင်ကုန်လက်ကျန်တွင် အမည်ပါသော ပစ္စည်းပေးသွင်းသူမှတ်တမ်းများကို အသုံးပြုရန် Suppliers စာမျက်နှာမှ ပစ္စည်းပေးသွင်းသူများကို ထည့်ပါ။',
      'Create the LPG Kg main stock product first. LPG 220g and LPG Viss are selling variants and cannot receive stock directly.': 'LPG Kg အဓိကလက်ကျန်ကုန်ပစ္စည်းကို အရင်ဖန်တီးပါ။ LPG 220g နှင့် LPG Viss သည် ရောင်းရန်မျိုးကွဲများဖြစ်သောကြောင့် လက်ကျန်ကို တိုက်ရိုက်ထည့်၍ မရပါ။',
      'Current incoming cost per kg: MMK ': 'လက်ရှိ ဝင်ကုန်တစ်ကီလိုကုန်ကျစရိတ်: MMK ',
      'Current cost per ': 'လက်ရှိ ကုန်ကျစရိတ် / ',
      'Enter LPG quantity directly in kg. No cylinder input is used.': 'LPG ပမာဏကို ကီလိုဖြင့် တိုက်ရိုက်ထည့်ပါ။ ဓာတ်ငွေ့အိုးအရေအတွက် ထည့်သွင်းမှုကို အသုံးမပြုပါ။',
      'Select an existing main stock product': 'ရှိပြီးသား အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ',
      'Customer sale': 'ဖောက်သည်အရောင်း',
      'Supplier payment': 'ပစ္စည်းပေးသွင်းသူထံ ပေးချေမှု',
      'Customer payment': 'ဖောက်သည်ထံမှ ရရှိသည့်ငွေ',
      'Initial customer payment': 'ဖောက်သည်၏ အစပေးချေမှု',
      'Initial supplier payment': 'ပစ္စည်းပေးသွင်းသူထံ အစပေးချေမှု',
      'Supplier payment adjustment': 'ပစ္စည်းပေးသွင်းသူပေးချေမှု ပြင်ဆင်ချက်',
      'Customer payment adjustment': 'ဖောက်သည်ပေးချေမှု ပြင်ဆင်ချက်',
      'Not enough stock.': 'လက်ကျန်မလုံလောက်ပါ။',
      'Sale {voucher}': 'အရောင်း {voucher}',
      'Purchase {product}': 'ဝယ်ယူမှု {product}',
      '{product} • Qty {qty} • Total {total} • Paid {paid}': '{product} • အရေအတွက် {qty} • စုစုပေါင်း {total} • ပေးပြီး {paid}',
      'Insufficient {type} stock. Available: {available}, trying to give: {given}.': 'ကျန်နေသော {type} ပမာဏ မလုံလောက်ပါ။ ရရှိနိုင်သည်: {available}၊ ပေးရန်ကြိုးစားသည်: {given}။',
      'Not enough stock. {product} has only {available} {unit} available for this voucher.': 'ဤဘောင်ချာအတွက် {product} တွင် {available} {unit} သာ လက်ကျန်ရှိပါသည်။',
      '{label}: MMK {amount}': '{label}: MMK {amount}',
      'Parent stock missing': 'အဓိကလက်ကျန် မတွေ့ပါ',
      'Voucher {voucher} • {date}': 'ဘောင်ချာ {voucher} • {date}',
      'Paid {paid} / {total} • Balance {balance}': 'ပေးပြီး {paid} / {total} • လက်ကျန် {balance}',
      'Payment date {date}': 'ပေးချေသည့်ရက် {date}',
      'Pay {supplier}': '{supplier} ထံ ပေးရန်',
      'Receive from {customer}': '{customer} ထံမှ လက်ခံရန်',
      'Outstanding: {balance}': 'ကျန်ငွေ: {balance}',
      'Balance {balance}': 'လက်ကျန် {balance}',
      'Paid {paid}': 'ပေးပြီး {paid}',
      'Received {amount}': 'လက်ခံရရှိ {amount}',
      'Adjustment {amount}': 'ပြင်ဆင်ငွေ {amount}',
      'Product {name} deleted.': 'ကုန်ပစ္စည်း {name} ကို ဖျက်ပြီးပါပြီ။',
      'Product {name} created.': 'ကုန်ပစ္စည်း {name} ကို ဖန်တီးပြီးပါပြီ။',
      'Set {type} quantity': '{type} အရေအတွက် သတ်မှတ်ရန်',
      'Delete {type} History': '{type} မှတ်တမ်းဖျက်ရန်',
      'Given {given} • Received {received}': 'ပေးလိုက်သည် {given} • ရရှိသည် {received}',
      'Cycle date: {date}': 'အဝင်အထွက်ရက်: {date}',
      'Active {category}: {qty}': 'လက်ရှိ {category}: {qty}',
      'English': 'English',
      'Burmese': 'မြန်မာ',
      'Language': 'ဘာသာစကား',
      'Switch to Burmese': 'မြန်မာဘာသာသို့ ပြောင်းရန်',
      'Switch to English': 'အင်္ဂလိပ်ဘာသာသို့ ပြောင်းရန်',
      'Kyal Sin Lay Energy & Tech': 'Kyal Sin Lay Energy & Tech',

      'Total Profit': 'စုစုပေါင်းအမြတ်',
      'Net Profit': 'အသားတင်အမြတ်',
      'Total to Pay: {amount}': 'ပေးရန်စုစုပေါင်း: {amount}',
      'Total to Receive: {amount}': 'ရရန်စုစုပေါင်း: {amount}',
      '{supplier} • {product}': '{supplier} • {product}',
      '{customer} • Voucher {voucher}': '{customer} • ဘောင်ချာ {voucher}',
      'Profit {amount}': 'အမြတ် {amount}',
      'Voucher {voucher} • {date} • {count} item(s)': 'ဘောင်ချာ {voucher} • {date} • {count} ခု',
      'No {category}s yet. Tap + to add one.': '{category} မရှိသေးပါ။ + ကိုနှိပ်၍ ထည့်ပါ။',
      'Add {category}': '{category} ထည့်ရန်',
      '{name} added as {category}': '{name} ကို {category} အဖြစ် ထည့်ပြီးပါပြီ။',
      'Cost per {unit} for this incoming': 'ဤဝင်ကုန်အတွက် {unit} တစ်ခုလျှင် ကုန်ကျစရိတ်',
      'Balance MMK {balance}': 'လက်ကျန် MMK {balance}',
      'Current incoming cost per kg: MMK {amount}': 'လက်ရှိ ဝင်ကုန်တစ်ကီလို ကုန်ကျစရိတ်: MMK {amount}',
      'Current cost per {unit}': 'လက်ရှိ {unit} တစ်ခုလျှင် ကုန်ကျစရိတ်',
      'Delete the voucher for "{customer}"? Stock sold on this voucher will be returned.': '"{customer}" အတွက် ဘောင်ချာကို ဖျက်မည်လား? ဤဘောင်ချာတွင် ရောင်းထားသော လက်ကျန်ကို ပြန်ထည့်ပေးပါမည်။',
      'Amount paid (total {amount})': 'ပေးပြီးငွေ (စုစုပေါင်း {amount})',
      'Date {date}': 'ရက်စွဲ {date}',
      'Cylinder type "{name}" added.': 'ဓာတ်ငွေ့အိုးအမျိုးအစား "{name}" ကို ထည့်ပြီးပါပြီ။',
      '{type} History': '{type} မှတ်တမ်း',
      'There is no history to delete for {type}.': '{type} အတွက် ဖျက်ရန် မှတ်တမ်းမရှိပါ။',
      'Transactions • {period}': 'အရောင်းအဝယ် • {period}',
      'Sales • {period}': 'အရောင်း • {period}',
      'Yearly Sales Summary - {year}': 'နှစ်စဉ်အရောင်းအနှစ်ချုပ် - {year}',
      'Transactions: {count}': 'အရောင်းအဝယ်: {count}',
      'Sales Report - {period}': 'အရောင်းအစီရင်ခံစာ - {period}',
      'Generated: {date}': 'ဖန်တီးသည့်ရက်: {date}',
      'Page {page}': 'စာမျက်နှာ {page}',
      'Customer • Voucher {voucher}': 'ဖောက်သည် • ဘောင်ချာ {voucher}',
      '{label} {amount}': '{label} {amount}',
      'product': 'ကုန်ပစ္စည်း',
      'products': 'ကုန်ပစ္စည်းများ',
      '1 {input} → {output} {stockUnit}': '1 {input} → {output} {stockUnit}',
      'Active {category}: 0': 'လက်ရှိ {category}: 0',
      'Active {category}: {qty} with customer': 'လက်ရှိ {category}: {qty} ဖောက်သည်ထံတွင်',
      'Active {category}: {qty} with us': 'လက်ရှိ {category}: {qty} ကျွန်ုပ်တို့ထံတွင်',
      'Add a Cylinder Type first': 'ဓာတ်ငွေ့အိုးအမျိုးအစားကို အရင်ထည့်ပါ',
      'Backup copied ({count} characters). For large backups, save it as a file instead of using the clipboard.': 'အရန်ဒေတာကို ကူးယူပြီးပါပြီ ({count} စာလုံး)။ ဒေတာအများအပြားအတွက် Clipboard အစား ဖိုင်အဖြစ် သိမ်းဆည်းပါ။',
      'Backup file saved ({count} characters).': 'အရန်ဒေတာဖိုင်ကို သိမ်းပြီးပါပြီ ({count} စာလုံး)။',
      'Balance: MMK {amount}': 'လက်ကျန်: MMK {amount}',
      'Current cost per {unit}: MMK {amount}': 'လက်ရှိ {unit} တစ်ခုလျှင် ကုန်ကျစရိတ်: MMK {amount}',
      'Current stock: {stock} {unit}': 'လက်ရှိလက်ကျန်: {stock} {unit}',
      'Customer owes us {qty}': 'ဖောက်သည်က ကျွန်ုပ်တို့ကို ပေးရန်ရှိသည် {qty}',
      'Customer units with us: {qty}': 'ဖောက်သည်ပစ္စည်း အရေအတွက် ကျွန်ုပ်တို့ထံရှိသည်: {qty}',
      'Customer: {customer}': 'ဖောက်သည်: {customer}',
      'Date: {date}': 'ရက်စွဲ: {date}',
      'Delete "{name}" ({kind})?\n\nIncoming records: {incoming}\nSaved sale items: {sales}\n\nParent stock products cannot be deleted while selling variants depend on them.': '"{name}" ({kind}) ကို ဖျက်မည်လား?\n\nဝင်ကုန်မှတ်တမ်း: {incoming}\nသိမ်းထားသော အရောင်းပစ္စည်းများ: {sales}\n\nရောင်းရန်မျိုးကွဲများက မှီခိုနေသော အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ဖျက်၍မရပါ။',
      'Delete "{name}"? Existing cylinder-cycle records will not be deleted.': '"{name}" ကို ဖျက်မည်လား? ရှိပြီးသား ဓာတ်ငွေ့အိုး အဝင်အထွက်မှတ်တမ်းများကို ဖျက်မည်မဟုတ်ပါ။',
      'Grand Total: MMK {amount}': 'စုစုပေါင်း: MMK {amount}',
      'In our possession: {qty}': 'ကျွန်ုပ်တို့ထံရှိသည်: {qty}',
      'Incoming date: {date}': 'ဝင်ကုန်ရက်: {date}',
      'Incoming quantity ({unit})': 'ဝင်ကုန်အရေအတွက် ({unit})',
      'LPG incoming: 1 kg → 1 kg (kg-only input)': 'LPG ဝင်ကုန်: 1 ကီလို → 1 ကီလို (ကီလိုဖြင့်သာ ထည့်သွင်းသည်)',
      'Missing': 'မတွေ့ပါ',
      'No customers added yet': 'ဖောက်သည် မထည့်ရသေးပါ',
      'Only cylinder types with an unsettled customer balance appear here.': 'ဖောက်သည်နှင့် မရှင်းရသေးသော ဓာတ်ငွေ့အိုးလက်ကျန်ရှိသည့် အမျိုးအစားများသာ ဤနေရာတွင် ပေါ်ပါမည်။',
      'Out with customers: {qty}': 'ဖောက်သည်များထံ ရှိနေသော အရေအတွက်: {qty}',
      'Paid: MMK {amount}': 'ပေးပြီး: MMK {amount}',
      'Period: {period}. Total Profit comes from the saved SaleItem profit. Expense here means manually recorded Income/Expense expenses; supplier purchase cost is already used when sale profit is calculated.': 'ကာလ: {period}။ စုစုပေါင်းအမြတ်သည် သိမ်းထားသော အရောင်းပစ္စည်းအမြတ်မှ ရရှိပါသည်။ အသုံးစရိတ်မှာ Income/Expense တွင် ကိုယ်တိုင်မှတ်တမ်းတင်ထားသော အသုံးစရိတ်ဖြစ်ပြီး ပစ္စည်းပေးသွင်းသူထံမှ ဝယ်ယူစရိတ်ကို အရောင်းအမြတ်တွက်ချက်ရာတွင် ထည့်သွင်းထားပြီးဖြစ်ပါသည်။',
      'Prepared For: {customer}': 'အတွက် ပြင်ဆင်ထားသည်: {customer}',
      'Select customer': 'ဖောက်သည်ကို ရွေးပါ',
      'Select cylinder type': 'ဓာတ်ငွေ့အိုးအမျိုးအစားကို ရွေးပါ',
      'Selling variant • Parent: {parent} • Sale unit: {unit}': 'ရောင်းရန်မျိုးကွဲ • အဓိကကုန်ပစ္စည်း: {parent} • ရောင်းယူနစ်: {unit}',
      'Showing {period}': '{period} ကို ပြသနေသည်',
      'Stock added: {qty} kg': 'ထပ်တိုးလက်ကျန်: {qty} ကီလို',
      'Stock added: {qty} {unit}': 'ထပ်တိုးလက်ကျန်: {qty} {unit}',
      'Stock: {stock} {unit}': 'လက်ကျန်: {stock} {unit}',
      'Stock: {stock} {unit} • Incoming: {incoming}': 'လက်ကျန်: {stock} {unit} • ဝင်ကုန်: {incoming}',
      'The backup is {count} characters long.': 'အရန်ဒေတာသည် စာလုံး {count} ရှိပါသည်။',
      'Total: MMK {amount}': 'စုစုပေါင်း: MMK {amount}',
      'Voucher for {customer}': '{customer} အတွက် ဘောင်ချာ',
      'We owe customer {qty}': 'ကျွန်ုပ်တို့က ဖောက်သည်ကို ပေးရန်ရှိသည် {qty}',
      'Your current physical quantity. Cycle entries update this automatically.': 'လက်ရှိ သင့်ထံရှိ အမှန်တကယ်အရေအတွက်ဖြစ်ပါသည်။ Cycle မှတ်တမ်းများသိမ်းသည့်အခါ ဤပမာဏကို အလိုအလျောက် ပြင်ဆင်ပါသည်။',
      '{category} • In our possession: {qty}': '{category} • ကျွန်ုပ်တို့ထံရှိသည်: {qty}',
      '{count} active customer(s)': 'ဖောက်သည်လက်ရှိ အရေအတွက် {count}',
      '{count} {label}': '{count} {label}',
      '{date} • {count} item(s) • {status}': '{date} • {count} ခု • {status}',
      '{qty} with customer • Customer owes us': '{qty} ဖောက်သည်ထံတွင် • ဖောက်သည်က ကျွန်ုပ်တို့ကို ပေးရန်ရှိသည်',
      '{qty} with us • We owe customer': '{qty} ကျွန်ုပ်တို့ထံတွင် • ကျွန်ုပ်တို့က ဖောက်သည်ကို ပေးရန်ရှိသည်',

      'This will also delete its linked Incoming Products records and supplier payment records. Saved sales using this product are protected and will block deletion.': 'ဤကုန်ပစ္စည်းနှင့် ချိတ်ဆက်ထားသော ဝင်ကုန်မှတ်တမ်းများနှင့် ပစ္စည်းပေးသွင်းသူထံ ပေးချေမှုမှတ်တမ်းများကိုလည်း ဖျက်ပါမည်။ သိမ်းထားသော အရောင်းမှတ်တမ်းများကြောင့် ဖျက်ခြင်းကို တားဆီးနိုင်ပါသည်။',
      'Remove product {name}?': 'ကုန်ပစ္စည်း {name} ကို ဖယ်ရှားမည်လား?',
      'This will reverse the converted stock amount and remove its linked supplier payment/payable record.': 'ပြောင်းလဲတွက်ချက်ထားသော လက်ကျန်ပမာဏကို မူလအတိုင်း ပြန်ပြင်ပြီး ချိတ်ဆက်ထားသော ပစ္စည်းပေးသွင်းသူထံ ပေးချေမှု/ပေးရန်ရှိငွေမှတ်တမ်းကို ဖယ်ရှားပါမည်။',
      '{product}: added {stock} {stockUnit} from {quantity} {inputUnit}.': '{product}: {quantity} {inputUnit} မှ {stock} {stockUnit} ကို ထည့်သွင်းပြီးပါပြီ။',
      '{qty} {inputUnit} → {stock} {stockUnit} • MMK {cost} per {unit}{supplier} • {date}': '{qty} {inputUnit} → {stock} {stockUnit} • တစ်{unit}လျှင် MMK {cost}{supplier} • {date}',
      '{customer} • {type}\n\n{given}\n{received}\n{date}': '{customer} • {type}\n\n{given}\n{received}\n{date}',
      'Given: {qty}': 'ပေးလိုက်သည်: {qty}',
      'Received: {qty}': 'ရရှိသည်: {qty}',
      'Quantity ({unit})': 'အရေအတွက် ({unit})',
      'This does not look like a POS backup. No recognized data sections were found.': 'ဤဖိုင်သည် POS အရန်ဒေတာဖိုင်ပုံစံ မဟုတ်ပါ။ အသိအမှတ်ပြုထားသော ဒေတာအပိုင်း မတွေ့ပါ။',
      'SharedPreferences rejected the database write.': 'ဒေတာဘေ့စ်သိမ်းဆည်းမှုကို စက်၏ SharedPreferences က လက်မခံပါ။',
      'Imported data could not be saved.': 'ထည့်သွင်းထားသော ဒေတာကို မသိမ်းနိုင်ပါ။',
      'Select the parent stock product for this selling variant.': 'ဤရောင်းရန်မျိုးကွဲအတွက် အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ။',
      'The selected parent stock product was not found.': 'ရွေးထားသော အဓိကလက်ကျန်ကုန်ပစ္စည်းကို မတွေ့ပါ။',
      'A product cannot subtract its own stock.': 'ကုန်ပစ္စည်းတစ်ခုသည် မိမိ၏ကိုယ်ပိုင်လက်ကျန်ကို မဖြတ်ယူနိုင်ပါ။',
      'A selling variant cannot use another selling variant as its parent. Choose the main stock product.': 'ရောင်းရန်မျိုးကွဲတစ်ခုသည် အခြားရောင်းရန်မျိုးကွဲကို အဓိကကုန်ပစ္စည်းအဖြစ် အသုံးမပြုနိုင်ပါ။ အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ။',
      'Stock used per sale unit must be greater than zero.': 'ရောင်းယူနစ်တစ်ခုအတွက် အသုံးပြုသည့် လက်ကျန်သည် သုညထက် ကြီးရပါမည်။',
      'A product with the same name, type, and sub type already exists.': 'အမည်၊ အမျိုးအစားနှင့် အခွဲအမျိုးအစား တူညီသော ကုန်ပစ္စည်း ရှိပြီးသားဖြစ်ပါသည်။',
      'Product could not be saved. Your previous saved data was kept.': 'ကုန်ပစ္စည်းကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Product could not be updated. Your previous saved data was kept.': 'ကုန်ပစ္စည်းကို ပြင်ဆင်၍ မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Select an existing main stock product before recording incoming stock.': 'ဝင်ကုန်လက်ကျန် မမှတ်တမ်းတင်မီ ရှိပြီးသား အဓိကလက်ကျန်ကုန်ပစ္စည်းကို ရွေးပါ။',
      'This product is a selling variant. Receive stock into its parent product instead.': 'ဤကုန်ပစ္စည်းသည် ရောင်းရန်မျိုးကွဲဖြစ်ပါသည်။ ၎င်း၏ အဓိကကုန်ပစ္စည်းထဲသို့ လက်ကျန်ထည့်ပါ။',
      'Incoming product could not be saved. Your previous saved data was kept.': 'ဝင်ကုန်ပစ္စည်းကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'This product is a parent stock product for {count} selling variant(s). Delete or reassign those variants first.': 'ဤကုန်ပစ္စည်းသည် ရောင်းရန်မျိုးကွဲ {count} ခု၏ အဓိကလက်ကျန်ကုန်ပစ္စည်း ဖြစ်ပါသည်။ ထိုမျိုးကွဲများကို အရင်ဖျက်ပါ သို့မဟုတ် အဓိကကုန်ပစ္စည်းပြောင်းသတ်မှတ်ပါ။',
      'This product is used by saved sales and cannot be deleted safely. Delete the incorrect Sale record first.': 'ဤကုန်ပစ္စည်းကို သိမ်းထားသော အရောင်းမှတ်တမ်းများတွင် အသုံးပြုထားသောကြောင့် လုံခြုံစွာ ဖျက်၍မရပါ။ မှားယွင်းသော အရောင်းမှတ်တမ်းကို အရင်ဖျက်ပါ။',
      'The selected product is missing its parent stock product.': 'ရွေးထားသော ကုန်ပစ္စည်းတွင် အဓိကလက်ကျန်ကုန်ပစ္စည်း မတွေ့ပါ။',
      'This incoming record cannot be deleted safely because some of the received stock has already been sold or otherwise consumed.': 'ရရှိထားသော လက်ကျန်အချို့ကို ရောင်းချပြီး သို့မဟုတ် အသုံးပြုပြီးဖြစ်သောကြောင့် ဤဝင်ကုန်မှတ်တမ်းကို လုံခြုံစွာ ဖျက်၍မရပါ။',
      'Incoming product deletion could not be saved. Your previous saved data was kept.': 'ဝင်ကုန်ပစ္စည်း ဖျက်ခြင်းကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'A sale must contain at least one item.': 'အရောင်းတစ်ခုတွင် အနည်းဆုံး ပစ္စည်းတစ်ခု ပါရပါမည်။',
      'Product "{product}" could not be matched to the product catalog.': 'ကုန်ပစ္စည်း "{product}" ကို ကုန်ပစ္စည်းစာရင်းနှင့် ကိုက်ညီစွာ မတွေ့နိုင်ပါ။',
      'Product "{product}" is linked to a missing parent stock product.': 'ကုန်ပစ္စည်း "{product}" သည် မတွေ့ရှိသော အဓိကလက်ကျန်ကုန်ပစ္စည်းနှင့် ချိတ်ဆက်ထားပါသည်။',
      'The stock conversion for "{product}" is invalid.': '"{product}" ၏ လက်ကျန်ပြောင်းလဲနှုန်းသည် မမှန်ကန်ပါ။',
      'Not enough stock for "{product}". Available: {available} {unit}, required: {required} {unit}.': '"{product}" အတွက် လက်ကျန်မလုံလောက်ပါ။ ရရှိနိုင်သည်: {available} {unit}၊ လိုအပ်သည်: {required} {unit}။',
      'Cylinder stock cannot be negative. Enter 0 or more.': 'ဓာတ်ငွေ့အိုးလက်ကျန်သည် အနုတ်မဖြစ်ရပါ။ ၀ သို့မဟုတ် ထို့ထက်များသော ပမာဏကို ထည့်ပါ။',
      'Cylinder type name cannot be empty.': 'ဓာတ်ငွေ့အိုးအမျိုးအစားအမည် မဖြစ်မနေထည့်ရပါမည်။',
      'A cylinder type with this name already exists in this category.': 'ဤအမျိုးအစားတွင် ဤအမည်ရှိသော ဓာတ်ငွေ့အိုးအမျိုးအစား ရှိပြီးသားဖြစ်ပါသည်။',
      'Cylinder type could not be saved. Your previous saved data was kept.': 'ဓာတ်ငွေ့အိုးအမျိုးအစားကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'This cylinder type is already used by Cylinder Cycles and cannot be deleted. Delete those cycle records first.': 'ဤဓာတ်ငွေ့အိုးအမျိုးအစားကို Cylinder Cycles တွင် အသုံးပြုထားပြီးဖြစ်သောကြောင့် ဖျက်၍မရပါ။ ထိုအဝင်အထွက်မှတ်တမ်းများကို အရင်ဖျက်ပါ။',
      'Cylinder type deletion could not be saved. Your previous saved data was kept.': 'ဓာတ်ငွေ့အိုးအမျိုးအစား ဖျက်ခြင်းကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Cylinder type not found.': 'ဓာတ်ငွေ့အိုးအမျိုးအစား မတွေ့ပါ။',
      'Cylinder quantity could not be saved. Your previous saved data was kept.': 'ဓာတ်ငွေ့အိုးအရေအတွက်ကို မသိမ်းနိုင်ပါ။ ယခင်သိမ်းထားသော ဒေတာကို ဆက်လက်ထိန်းသိမ်းထားပါသည်။',
      'Cylinder quantities cannot be negative.': 'ဓာတ်ငွေ့အိုးအရေအတွက်သည် အနုတ်မဖြစ်ရပါ။',
      'Myanmar PDF font is missing.': 'Myanmar PDF ဖောင့် မတွေ့ပါ။',
      'PDF generation failed: {error}': 'PDF ဖန်တီးမှု မအောင်မြင်ပါ: {error}',
      'Cylinder stock is entered and adjusted on the Cylinder Types page.': 'ဓာတ်ငွေ့အိုးလက်ကျန်ကို Cylinder Types စာမျက်နှာတွင် ထည့်သွင်းပြီး ပြင်ဆင်ပါသည်။',

      'Quantity for {product} must be greater than zero.': '{product} အတွက် အရေအတွက်သည် သုညထက် ကြီးရပါမည်။',
      'Could not save data: {error}': 'ဒေတာသိမ်းဆည်း၍ မရပါ: {error}',
      'Stored data could not be loaded safely: {error}': 'သိမ်းထားသောဒေတာကို လုံခြုံစွာ ဖတ်မရပါ: {error}',
      'Another product already has the same name, type, and sub type.': 'အမည်၊ အမျိုးအစားနှင့် အခွဲအမျိုးအစား တူညီသော အခြားကုန်ပစ္စည်း ရှိပြီးသားဖြစ်ပါသည်။',

      'Remove product {name}?\n\n{details}': 'ကုန်ပစ္စည်း {name} ကို ဖယ်ရှားမည်လား?\n\n{details}',
      '{given} • {received}\n{date} • {direction}': '{given} • {received}\n{date} • {direction}',
      '{given} • {received} • {date}': '{given} • {received} • {date}',
      '{product} • {qty} {inputUnit} • {adds} {stockUnit}\n\n{details}': '{product} • {qty} {inputUnit} • ထပ်တိုး {adds} {stockUnit}\n\n{details}',

      'Given {qty}': 'ပေးလိုက်သည် {qty}',
      'Received {qty}': 'ရရှိသည် {qty}',
      '{given} • {received}': '{given} • {received}',

      // Updated translations for newer screens and remaining user-facing text.
      'Capital': 'မတည်ငွေ',
      'Set Starting Capital': 'စတင်မတည်ငွေ သတ်မှတ်ရန်',
      'This amount is saved once as the fixed opening balance and cannot be edited from the Capital page.': 'ဤပမာဏကို အစဖွင့်လက်ကျန်အဖြစ် တစ်ကြိမ်သာ သိမ်းဆည်းပြီး မတည်ငွေစာမျက်နှာမှ ပြင်ဆင်၍မရပါ။',
      'Starting Capital (MMK)': 'စတင်မတည်ငွေ (MMK)',
      'Capital tracking start date': 'မတည်ငွေစာရင်း စတင်သည့်ရက်',
      'Tracking Start Date': 'စာရင်းစတင်သည့်ရက်',
      'Enter a valid starting capital amount.': 'မှန်ကန်သော စတင်မတည်ငွေပမာဏကို ထည့်ပါ။',
      'Set and Lock': 'သတ်မှတ်ပြီး အတည်ပြုရန်',
      'Starting capital has been set and locked.': 'စတင်မတည်ငွေကို သတ်မှတ်ပြီး အတည်ပြုပြီးပါပြီ။',
      'Starting capital for this day': 'ဤနေ့၏ စတင်မတည်ငွေ',
      'Added today': 'ယနေ့ ထပ်ထည့်ငွေ',
      'Extracted today': 'ယနေ့ ထုတ်ယူငွေ',
      'Left capital at day end': 'နေ့ကုန် မတည်ငွေလက်ကျန်',
      'Starting Capital (Fixed)': 'စတင်မတည်ငွေ (သတ်မှတ်ပြီး)',
      'Not set yet': 'မသတ်မှတ်ရသေးပါ',
      'Set once to begin capital tracking.': 'မတည်ငွေစာရင်း စတင်ရန် တစ်ကြိမ် သတ်မှတ်ပါ။',
      'Set Capital': 'မတည်ငွေ သတ်မှတ်ရန်',
      'Today Updated Capital': 'ယနေ့ ပြင်ဆင်ပြီး မတည်ငွေ',
      'Total to Receive Amount': 'စုစုပေါင်း ရရန်ငွေ',
      'Total Capital with To Receive': 'ရရန်ငွေပါ ထည့်တွက်ထားသော စုစုပေါင်းမတည်ငွေ',
      'Updated capital + outstanding customer balances': 'ပြင်ဆင်ပြီး မတည်ငွေ + ဖောက်သည်ထံမှ ရရန်ကျန်ငွေ',
      'Daily Capital Reports': 'နေ့စဉ် မတည်ငွေ အစီရင်ခံစာများ',
      'Expand a date to see that day’s opening capital and remaining capital after additions and extractions.': 'ရက်စွဲတစ်ခုကို ဖွင့်၍ ထိုနေ့၏ အစဖွင့်မတည်ငွေနှင့် ထပ်ထည့်/ထုတ်ယူပြီးနောက် ကျန်ငွေကို ကြည့်ပါ။',
      'No capital activity has been recorded yet.': 'မတည်ငွေ လှုပ်ရှားမှုမှတ်တမ်း မရှိသေးပါ။',
      'Set your starting capital to see today’s updated capital, outstanding receivables, total capital with receivables, and daily capital reports.': 'ယနေ့၏ ပြင်ဆင်ပြီးမတည်ငွေ၊ ရရန်ကျန်ငွေ၊ ရရန်ငွေပါ စုစုပေါင်းမတည်ငွေနှင့် နေ့စဉ်မတည်ငွေအစီရင်ခံစာများကို ကြည့်ရန် စတင်မတည်ငွေကို သတ်မှတ်ပါ။',
      'Amount (MMK)': 'ပမာဏ (MMK)',
      'Enter a description and a valid amount.': 'ဖော်ပြချက်နှင့် မှန်ကန်သော ပမာဏကို ထည့်ပါ။',
      'Unspecified': 'မသတ်မှတ်ထားပါ',
      'Unnamed Product': 'အမည်မဖော်ပြထားသော ကုန်ပစ္စည်း',
      'Other': 'အခြား',
      'No chart data for this period.': 'ဤကာလအတွက် ဇယားဒေတာ မရှိပါ။',
      'Total Paid': 'စုစုပေါင်း ပေးချေပြီးငွေ',
      'COGS': 'ရောင်းချခဲ့သော ကုန်ပစ္စည်းကုန်ကျစရိတ် (COGS)',
      'Gross Profit': 'စုစုပေါင်းအမြတ်',
      'Gross Margin': 'အမြတ်နှုန်း',
      'Add Income': 'ဝင်ငွေ ထည့်ရန်',
      'Add Expense': 'အသုံးစရိတ် ထည့်ရန်',
      'Wi-Fi Sync': 'Wi-Fi ထပ်တူပြုခြင်း',
      'Wi-Fi server started.': 'Wi-Fi server စတင်ပြီးပါပြီ။',
      'Client mode is ready. Enter the server connection code, or enter the server IP and pairing token, then pair.': 'Client mode အဆင်သင့်ဖြစ်ပါပြီ။ Server ချိတ်ဆက်မှုကုဒ်ကို ထည့်ပါ၊ သို့မဟုတ် Server IP နှင့် pairing token ကို ထည့်ပြီး ချိတ်ဆက်ပါ။',
      'Client settings saved.': 'Client ဆက်တင်များကို သိမ်းပြီးပါပြီ။',
      'Paste the server connection code first.': 'Server ချိတ်ဆက်မှုကုဒ်ကို အရင်ကူးထည့်ပါ။',
      'First Wi-Fi pairing': 'ပထမဆုံး Wi-Fi ချိတ်ဆက်ခြင်း',
      'This device already contains POS data. For safety, first pairing replaces this device with the server data. Export a backup first if this device contains anything you need.': 'ဤစက်တွင် POS ဒေတာ ရှိပြီးသားဖြစ်ပါသည်။ လုံခြုံရေးအတွက် ပထမဆုံးချိတ်ဆက်သည့်အခါ ဤစက်၏ဒေတာကို Server ဒေတာဖြင့် အစားထိုးပါမည်။ ဤစက်ရှိ ဒေတာများကို လိုအပ်ပါက အရင်ဆုံး အရန်ဖိုင်ထုတ်ယူထားပါ။',
      'Use Server Data': 'Server ဒေတာကို အသုံးပြုရန်',
      'Paired successfully. Automatic sync is now enabled.': 'ချိတ်ဆက်မှု အောင်မြင်ပါပြီ။ အလိုအလျောက် ထပ်တူပြုခြင်းကို ဖွင့်ထားပါပြီ။',
      'No POS server was found on this Wi-Fi network.': 'ဤ Wi-Fi ကွန်ရက်တွင် POS server မတွေ့ပါ။',
      'POS servers found': 'POS server များကို တွေ့ရှိပါသည်',
      'Server mode': 'Server mode',
      'Client mode': 'Client mode',
      'Wi-Fi sync is off': 'Wi-Fi ထပ်တူပြုခြင်း ပိတ်ထားသည်',
      'Off': 'ပိတ်ထားသည်',
      'Server': 'Server',
      'Client': 'Client',
      'Server settings': 'Server ဆက်တင်များ',
      'Port': 'Port',
      'Use the same Wi-Fi network on every POS device.': 'POS စက်အားလုံးကို Wi-Fi ကွန်ရက်တစ်ခုတည်းနှင့် ချိတ်ဆက်ထားပါ။',
      'No local IPv4 address was found yet.': 'Local IPv4 လိပ်စာ မတွေ့ရသေးပါ။',
      'Connect using one of these server addresses:': 'အောက်ပါ Server လိပ်စာများထဲမှ တစ်ခုကို အသုံးပြုပြီး ချိတ်ဆက်ပါ။',
      'Copy': 'ကူးယူရန်',
      'Start Server': 'Server စတင်ရန်',
      'Stop': 'ရပ်ရန်',
      'Connection code': 'ချိတ်ဆက်မှုကုဒ်',
      'Copy Code': 'ကုဒ် ကူးယူရန်',
      'Scan this code on another device': 'အခြားစက်တစ်လုံးဖြင့် ဤကုဒ်ကို Scan ဖတ်ပါ',
      'Show QR': 'QR ပြရန်',
      'Client connection': 'Client ချိတ်ဆက်မှု',
      'Server IP address': 'Server IP လိပ်စာ',
      'Pairing token': 'ချိတ်ဆက်မှု အတည်ပြုကုဒ်',
      'Connection code from server': 'Server မှ ချိတ်ဆက်မှုကုဒ်',
      'Paste & Pair': 'ကူးထည့်ပြီး ချိတ်ဆက်ရန်',
      'Find Server': 'Server ရှာရန်',
      'Save Connection': 'ချိတ်ဆက်မှုကို သိမ်းရန်',
      'Automatic synchronization': 'အလိုအလျောက် ထပ်တူပြုခြင်း',
      'Retries automatically after Wi-Fi reconnects while the POS app is running.': 'POS အက်ပ် ဖွင့်ထားစဉ် Wi-Fi ပြန်ချိတ်ဆက်သည့်အခါ အလိုအလျောက် ပြန်ကြိုးစားပါမည်။',
      'Sync Now': 'ယခု ထပ်တူပြုရန်',
      'Pair / Re-pair': 'ချိတ်ဆက်ရန် / ပြန်ချိတ်ဆက်ရန်',
      'Local changes are waiting to sync.': 'စက်တွင်းပြောင်းလဲမှုများကို ထပ်တူပြုရန် စောင့်နေပါသည်။',
      'Choose Server on the main POS device. Choose Client on additional devices. After first pairing, the client stores its secure pairing information and automatically reconnects when the Wi-Fi server becomes reachable again.': 'အဓိက POS စက်တွင် Server ကို ရွေးပါ။ အခြားစက်များတွင် Client ကို ရွေးပါ။ ပထမဆုံးချိတ်ဆက်ပြီးနောက် Client သည် လုံခြုံသော ချိတ်ဆက်မှုအချက်အလက်ကို သိမ်းဆည်းထားပြီး Wi-Fi Server ပြန်လည်ရရှိနိုင်သည့်အခါ အလိုအလျောက် ပြန်ချိတ်ဆက်ပါမည်။',
      'Search by store name': 'ဆိုင်အမည်ဖြင့် ရှာရန်',
      'No stores match your search.': 'ရှာဖွေမှုနှင့် ကိုက်ညီသော ဆိုင်မရှိပါ။',
      '1 outstanding voucher': 'မရှင်းရသေးသော ဘောင်ချာ ၁ စောင်',
      'Search customer name or phone': 'ဖောက်သည်အမည် သို့မဟုတ် ဖုန်းနံပါတ်ဖြင့် ရှာရန်',
      'Clear search': 'ရှာဖွေမှုကို ရှင်းရန်',
      'No customers match your search.': 'ရှာဖွေမှုနှင့် ကိုက်ညီသော ဖောက်သည်မရှိပါ။',
      'Try another customer name or phone number.': 'အခြားဖောက်သည်အမည် သို့မဟုတ် ဖုန်းနံပါတ်ဖြင့် ရှာကြည့်ပါ။',
      '{count} outstanding vouchers': 'မရှင်းရသေးသော ဘောင်ချာ {count} စောင်',
      'Voucher {voucher}': 'ဘောင်ချာ {voucher}',
      'Added: {amount}': 'ထပ်ထည့်ငွေ: {amount}',
      'Extracted: {amount}': 'ထုတ်ယူငွေ: {amount}',
      'Locked since {date}': '{date} မှစ၍ အတည်ပြုထားသည်',
      'Yearly Sales Report - {year}': 'နှစ်စဉ်အရောင်းအစီရင်ခံစာ - {year}',
      '{given} • {received}\n{direction}': '{given} • {received}\n{direction}',
      '{qty} with customer': 'ဖောက်သည်ထံတွင် {qty}',
      '{qty} with us': 'ကျွန်ုပ်တို့ထံတွင် {qty}',
      'Found POS server at {host}:{port}. Paste its connection code to pair.': 'POS server ကို {host}:{port} တွင် တွေ့ရှိပါသည်။ ချိတ်ဆက်ရန် ၎င်း၏ connection code ကို ကူးထည့်ပါ။',
      'Paired devices seen: {count}': 'ချိတ်ဆက်ထားသော စက်များ: {count}',
      'Last sync: {time}': 'နောက်ဆုံး ထပ်တူပြုချိန်: {time}',
      'Last sync resolved {count} conflict(s) using the server copy for conflicting non-stock fields.': 'နောက်ဆုံး ထပ်တူပြုချိန်တွင် ကွဲလွဲမှု {count} ခုကို ဖြေရှင်းရာ၌ လက်ကျန်နှင့်မသက်ဆိုင်သော ကွဲလွဲနေသည့်အချက်အလက်များအတွက် Server မိတ္တူကို အသုံးပြုခဲ့သည်။',
      'Your role does not have access to this area.': 'သင့်အခန်းကဏ္ဍတွင် ဤနေရာကို အသုံးပြုခွင့်မရှိပါ။',
      'Sign out': 'အကောင့်မှ ထွက်ရန်',
      'Only Owner or Admin can export data.': 'Owner သို့မဟုတ် Admin သာ ဒေတာကို ထုတ်ယူနိုင်ပါသည်။',
      'Only Owner or Admin can restore a backup.': 'Owner သို့မဟုတ် Admin သာ အရန်ဒေတာကို ပြန်လည်ရယူနိုင်ပါသည်။',
      'Example: 192.168.1.20': 'ဥပမာ - 192.168.1.20',
      'John/Jane Doe': 'အမည်မဖော်ပြထားပါ',
      'N/A': 'မရှိပါ',
      'Voucher No: {voucher}': 'ဘောင်ချာအမှတ်: {voucher}',
      'Ready.': 'အသင့်ဖြစ်ပါပြီ။',
      'Server address copied.': 'Server လိပ်စာကို ကူးယူပြီးပါပြီ။',
      'Connection code copied.': 'ချိတ်ဆက်မှုကုဒ်ကို ကူးယူပြီးပါပြီ။',
      'Other Income': 'အခြားဝင်ငွေ',
      'Monthly Sales Trend': 'လစဉ်အရောင်းလမ်းကြောင်း',
      'Monthly Financial Breakdown': 'လစဉ်ဘဏ္ဍာရေးအသေးစိတ်',
      'Sales by Month': 'လအလိုက်အရောင်း',
      'Top Products by Revenue': 'ဝင်ငွေအများဆုံး ကုန်ပစ္စည်းများ',
      'Top Products by Profit': 'အမြတ်အများဆုံး ကုန်ပစ္စည်းများ',
      'Payment Methods': 'ပေးချေနည်းလမ်းများ',
      'Expense Breakdown': 'အသုံးစရိတ် အသေးစိတ်',
      'Customers by Sales': 'အရောင်းပမာဏအလိုက် ဖောက်သည်များ',
      'Outstanding Receivables': 'မရရှိသေးသော ရရန်ငွေများ',
      'Daily Sales Trend': 'နေ့စဉ်အရောင်းလမ်းကြောင်း',
      'Sales by Hour': 'နာရီအလိုက်အရောင်း',
      'Financial Overview': 'ဘဏ္ဍာရေးအနှစ်ချုပ်',
      'Top Customers': 'အရောင်းအများဆုံး ဖောက်သည်များ',
      'Sales Amount': 'အရောင်းတန်ဖိုး',
      'Invoices': 'ဘောင်ချာအရေအတွက်',
      'Jan': 'ဇန်',
      'Feb': 'ဖေ',
      'Mar': 'မတ်',
      'Apr': 'ဧ',
      'Jun': 'ဇွန်',
      'Jul': 'ဇူ',
      'Aug': 'ဩ',
      'Sep': 'စက်',
      'Oct': 'အောက်',
      'Nov': 'နို',
      'Dec': 'ဒီ',
      'Select whether legacy loose gas is sold by kg or viss.': 'ယခင် loose gas ကို ကီလိုဖြင့်လား၊ ပိဿာဖြင့်လား ရောင်းမည်ကို ရွေးပါ။',
      'Your account is not permitted to record sales.': 'သင့်အကောင့်တွင် အရောင်းမှတ်တမ်းတင်ခွင့် မရှိပါ။',
      'Only Owner or Admin can change a saved sale.': 'သိမ်းထားသော အရောင်းမှတ်တမ်းကို Owner သို့မဟုတ် Admin သာ ပြင်ဆင်နိုင်ပါသည်။',
      'Owner or Admin approval is required to delete a sale.': 'အရောင်းမှတ်တမ်းကို ဖျက်ရန် Owner သို့မဟုတ် Admin ၏ အတည်ပြုချက် လိုအပ်ပါသည်။',
      'Cylinder category must be 48 kg or 10v.': 'ဓာတ်ငွေ့အိုးအမျိုးအစားသည် 48 kg သို့မဟုတ် 10v ဖြစ်ရပါမည်။',
      'This product is missing its parent stock product.': 'ဤကုန်ပစ္စည်း၏ အဓိကလက်ကျန်ကုန်ပစ္စည်းကို မတွေ့ပါ။',
      'Set up the Owner account': 'ပိုင်ရှင်အကောင့် စတင်ပြင်ဆင်ရန်',
      'This protects users, sales, backups, and device access.': 'ဤစာမျက်နှာသည် အသုံးပြုသူများ၊ အရောင်းမှတ်တမ်းများ၊ အရန်ဒေတာများနှင့် စက်အသုံးပြုခွင့်ကို ကာကွယ်ပေးသည်။',
      'Owner name': 'ပိုင်ရှင်အမည်',
      'Owner PIN (4–12 digits)': 'ပိုင်ရှင် PIN (ဂဏန်း ၄–၁၂ လုံး)',
      'Confirm PIN': 'PIN အတည်ပြုရန်',
      'Create Owner account': 'ပိုင်ရှင်အကောင့် ဖန်တီးရန်',
      'PINs do not match.': 'PIN များ ကိုက်ညီမှုမရှိပါ။',
      'Creating…': 'ဖန်တီးနေသည်…',
      'Create account': 'အကောင့်ဖန်တီးရန်',
      'Sign in to POS': 'POS စနစ်သို့ ဝင်ရောက်ရန်',
      'First account becomes Owner. Its username is fixed as owner.': 'ပထမဆုံးဖန်တီးသော အကောင့်သည် ပိုင်ရှင်အကောင့် ဖြစ်လာမည်။ အသုံးပြုသူအမည်ကို owner ဟု သတ်မှတ်ထားသည်။',
      'New accounts start with Cashier permissions.': 'အကောင့်အသစ်များသည် ငွေကိုင်ခွင့်ပြုချက်များဖြင့် စတင်မည်။',
      'Use your assigned username and PIN. If this device has not synced yet, you can create a local account.': 'သင့်အား သတ်မှတ်ပေးထားသော အသုံးပြုသူအမည်နှင့် PIN ကို အသုံးပြုပါ။ ဤစက်သည် မချိတ်ဆက်ရသေးပါက စက်တွင်းအကောင့်တစ်ခု ဖန်တီးနိုင်သည်။',
      'Full name': 'အမည်အပြည့်အစုံ',
      'Username (3+ characters)': 'အသုံးပြုသူအမည် (အနည်းဆုံး စာလုံး ၃ လုံး)',
      'Username': 'အသုံးပြုသူအမည်',
      'PIN (4–12 digits)': 'PIN (ဂဏန်း ၄–၁၂ လုံး)',
      'PIN': 'PIN',
      'Please wait…': 'ခဏစောင့်ပါ…',
      'Sign up': 'အကောင့်ဖွင့်ရန်',
      'Sign in': 'ဝင်ရောက်ရန်',
      'Already have an account? Sign in': 'အကောင့်ရှိပြီးသားလား။ ဝင်ရောက်ပါ',
      'New to this device? Sign up': 'ဤစက်တွင် အကောင့်အသစ်လား။ အကောင့်ဖွင့်ပါ',
      'Incorrect username or PIN. If this device has not synced, use Sign up.': 'အသုံးပြုသူအမည် သို့မဟုတ် PIN မှားယွင်းနေသည်။ ဤစက်နှင့် မချိတ်ဆက်ရသေးပါက အကောင့်ဖွင့်ပါ။',
      'Add user': 'အသုံးပြုသူထည့်ရန်',
      'Name': 'အမည်',
      'Role': 'အခန်းကဏ္ဍ',
      'Approval required': 'အတည်ပြုချက် လိုအပ်သည်',
      '{action} requires Owner or Admin approval.': '{action} ကို ဆောင်ရွက်ရန် ပိုင်ရှင် သို့မဟုတ် စီမံခန့်ခွဲသူ၏ အတည်ပြုချက် လိုအပ်သည်။',
      'Approver PIN': 'အတည်ပြုပေးသူ၏ PIN',
      'Approve': 'အတည်ပြုရန်',
      'PIN must be 4–12 digits.': 'PIN သည် ဂဏန်း ၄ လုံးမှ ၁၂ လုံးအထိ ဖြစ်ရမည်။',
      'Owner account already exists.': 'ပိုင်ရှင်အကောင့် ရှိပြီးသားဖြစ်သည်။',
      'Only Owner or Admin can change role permissions.': 'အခန်းကဏ္ဍခွင့်ပြုချက်များကို ပိုင်ရှင် သို့မဟုတ် စီမံခန့်ခွဲသူသာ ပြောင်းလဲနိုင်သည်။',
      'This permission is reserved for the Admin role.': 'ဤခွင့်ပြုချက်ကို စီမံခန့်ခွဲသူအခန်းကဏ္ဍအတွက်သာ သတ်မှတ်ထားသည်။',
      'Enter your name.': 'သင့်အမည်ကို ထည့်ပါ။',
      'Choose a unique username of at least 3 characters.': 'အနည်းဆုံး စာလုံး ၃ လုံးပါပြီး အခြားသူနှင့် မတူသော အသုံးပြုသူအမည်ကို ရွေးပါ။',
      'Only Owner or Admin can add users.': 'အသုံးပြုသူများကို ပိုင်ရှင် သို့မဟုတ် စီမံခန့်ခွဲသူသာ ထည့်နိုင်သည်။',
      'There can be only one Owner.': 'ပိုင်ရှင်အကောင့် တစ်ခုသာ ရှိနိုင်သည်။',
      'This account cannot be changed.': 'ဤအကောင့်ကို ပြောင်းလဲ၍ မရပါ။',
      'Role permissions': 'အခန်းကဏ္ဍခွင့်ပြုချက်များ',
      'Tap a role to expand its permissions. Choose which sections each role can access. Owner always retains full access.': 'ခွင့်ပြုချက်များကို ကြည့်ရန် အခန်းကဏ္ဍတစ်ခုကို နှိပ်ပါ။ အခန်းကဏ္ဍတစ်ခုစီ ဝင်ရောက်နိုင်သည့် ကဏ္ဍများကို ရွေးချယ်ပါ။ ပိုင်ရှင်သည် အပြည့်အဝ ဝင်ရောက်ခွင့်ကို အမြဲရရှိမည်။',
      '{count} permissions enabled': 'ခွင့်ပြုချက် {count} ခု ဖွင့်ထားသည်',
      'Inventory & incoming stock': 'ကုန်ပစ္စည်းလက်ကျန်နှင့် ဝင်ကုန်',
      'Customers & suppliers': 'ဖောက်သည်များနှင့် ပစ္စည်းပေးသွင်းသူများ',
      'Edit saved sales': 'သိမ်းထားသော အရောင်းများကို တည်းဖြတ်ရန်',
      'Delete sales': 'အရောင်းမှတ်တမ်းများ ဖျက်ရန်',
      'Export data': 'ဒေတာထုတ်ယူရန်',
      'Restore backups': 'အရန်ဒေတာ ပြန်လည်ရယူရန်',
      'Manage users': 'အသုံးပြုသူများ စီမံရန်',
      'Security Center & role permissions': 'လုံခြုံရေးစင်တာနှင့် အခန်းကဏ္ဍခွင့်ပြုချက်များ',
      'Device settings': 'စက်ဆက်တင်များ',
      'Branch settings': 'ဆိုင်ခွဲဆက်တင်များ',
      'License settings': 'လိုင်စင်ဆက်တင်များ',
      'Never': 'မရှိသေးပါ',
      'Mode: {mode}': 'လုပ်ဆောင်မှုပုံစံ: {mode}',
      'Users, roles, PINs and the admin activity log sync over Wi-Fi with the rest of your POS data. No cloud server is used.': 'အသုံးပြုသူများ၊ အခန်းကဏ္ဍများ၊ PIN များနှင့် စီမံခန့်ခွဲသူ လုပ်ဆောင်ချက်မှတ်တမ်းများကို POS ဒေတာများနှင့်အတူ Wi-Fi မှတစ်ဆင့် ထပ်တူပြုပါသည်။ Cloud server ကို အသုံးမပြုပါ။',
      'Last sync: {last}{pending}': 'နောက်ဆုံး ထပ်တူပြုချိန်: {last}{pending}',
      'changes pending': 'ပြောင်းလဲမှုများ ထပ်တူပြုရန် ကျန်ရှိနေသည်',
      'Wi-Fi Sync settings': 'Wi-Fi ထပ်တူပြုခြင်း ဆက်တင်များ',
      'Sync now': 'ယခု ထပ်တူပြုရန်',
      'Security Center': 'လုံခြုံရေးစင်တာ',
      'Device {deviceId}': 'စက် {deviceId}',
      'Audit tampering detected': 'စစ်ဆေးမှတ်တမ်းကို ပြုပြင်ထားသည်ကို တွေ့ရှိသည်',
      'Restore a trusted backup and investigate this device.': 'ယုံကြည်ရသော အရန်ဒေတာကို ပြန်လည်ရယူပြီး ဤစက်ကို စစ်ဆေးပါ။',
      'Users & roles': 'အသုံးပြုသူများနှင့် အခန်းကဏ္ဍများ',
      'Disabled': 'ပိတ်ထားသည်',
      'Wi-Fi sync': 'Wi-Fi ထပ်တူပြုခြင်း',
      'Admin activity log': 'စီမံခန့်ခွဲသူ လုပ်ဆောင်ချက်မှတ်တမ်း',
      'Owner': 'ပိုင်ရှင်',
      'Admin': 'စီမံခန့်ခွဲသူ',
      'Manager': 'မန်နေဂျာ',
      'Cashier': 'ငွေကိုင်',
      'System': 'စနစ်',
      'Owner account created': 'ပိုင်ရှင်အကောင့် ဖန်တီးပြီး',
      'Failed sign in': 'ဝင်ရောက်ရန် ကြိုးပမ်းမှု မအောင်မြင်ပါ',
      'Role permissions changed': 'အခန်းကဏ္ဍခွင့်ပြုချက်များ ပြောင်းလဲခဲ့သည်',
      'Self sign-up created': 'ကိုယ်တိုင် အကောင့်ဖွင့်ခဲ့သည်',
      'Sensitive action approved': 'အရေးကြီးသော လုပ်ဆောင်ချက်ကို အတည်ပြုခဲ့သည်',
      'Signed in': 'ဝင်ရောက်ပြီး',
      'Signed out': 'ထွက်ပြီး',
      'User created': 'အသုံးပြုသူ ဖန်တီးပြီး',
      'User enabled': 'အသုံးပြုသူကို ဖွင့်ထားသည်',
      'User disabled': 'အသုံးပြုသူကို ပိတ်ထားသည်',
      'enabled': 'ဖွင့်ထားသည်',
      'disabled': 'ပိတ်ထားသည်',
  };

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_languageKey);
    if (saved == 'my' || saved == 'en') {
      language.value = saved!;
    }
  }

  static bool get isBurmese => language.value == 'my';

  /// User-facing tooltip for the language toggle. The UI does not need to
  /// know the translation keys used for the action.
  static String get languageButtonTooltip =>
      isBurmese ? t('Switch to English') : t('Switch to Burmese');

  static Future<void> setLanguage(String code) async {
    final normalized = code == 'my' ? 'my' : 'en';
    language.value = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, normalized);
  }

  static Future<void> toggle() => setLanguage(isBurmese ? 'en' : 'my');

  /// Translate user-facing StateError/exception messages while preserving
  /// dynamic values such as product names, quantities, and file paths.
  static String error(Object error) {
    final raw = error is StateError ? error.message.toString() : error.toString();


    final quantity = RegExp(r'^Quantity for (.+) must be greater than zero\.$')
        .firstMatch(raw);
    if (quantity != null) {
      return f('Quantity for {product} must be greater than zero.', {
        'product': quantity.group(1)!,
      });
    }

    final productMatch = RegExp(
      r'^Product "(.+)" could not be matched to the product catalog\.$',
    ).firstMatch(raw);
    if (productMatch != null) {
      return f('Product "{product}" could not be matched to the product catalog.', {
        'product': productMatch.group(1)!,
      });
    }

    final linkedMatch = RegExp(
      r'^Product "(.+)" is linked to a missing parent stock product\.$',
    ).firstMatch(raw);
    if (linkedMatch != null) {
      return f('Product "{product}" is linked to a missing parent stock product.', {
        'product': linkedMatch.group(1)!,
      });
    }

    final conversionMatch = RegExp(
      r'^The stock conversion for "(.+)" is invalid\.$',
    ).firstMatch(raw);
    if (conversionMatch != null) {
      return f('The stock conversion for "{product}" is invalid.', {
        'product': conversionMatch.group(1)!,
      });
    }

    final stockMatch = RegExp(
      r'^Not enough stock for "(.+)"\. Available: (.+) (.+), required: (.+) (.+)\.$',
    ).firstMatch(raw);
    if (stockMatch != null) {
      return f('Not enough stock for "{product}". Available: {available} {unit}, required: {required} {unit}.', {
        'product': stockMatch.group(1)!,
        'available': stockMatch.group(2)!,
        'unit': stockMatch.group(3)!,
        'required': stockMatch.group(4)!,
      });
    }

    final insufficientMatch = RegExp(
      r'^Insufficient (.+) stock\. Available: (.+), trying to give: (.+)\.$',
    ).firstMatch(raw);
    if (insufficientMatch != null) {
      return f('Insufficient {type} stock. Available: {available}, trying to give: {given}.', {
        'type': insufficientMatch.group(1)!,
        'available': insufficientMatch.group(2)!,
        'given': insufficientMatch.group(3)!,
      });
    }

    final voucherStockMatch = RegExp(
      r'^Not enough stock\. (.+) has only (.+) (.+) available for this voucher\.$',
    ).firstMatch(raw);
    if (voucherStockMatch != null) {
      return f('Not enough stock. {product} has only {available} {unit} available for this voucher.', {
        'product': voucherStockMatch.group(1)!,
        'available': voucherStockMatch.group(2)!,
        'unit': voucherStockMatch.group(3)!,
      });
    }

    final childrenMatch = RegExp(
      r'^This product is a parent stock product for (\d+) selling variant\(s\)\. Delete or reassign those variants first\.$',
    ).firstMatch(raw);
    if (childrenMatch != null) {
      return f('This product is a parent stock product for {count} selling variant(s). Delete or reassign those variants first.', {
        'count': childrenMatch.group(1)!,
      });
    }

    if (raw.startsWith('Could not save data: ')) {
      return f('Could not save data: {error}', {
        'error': UiTranslation.error(raw.substring('Could not save data: '.length)),
      });
    }

    if (raw.startsWith('PDF generation failed: ')) {
      return f('PDF generation failed: {error}', {
        'error': UiTranslation.error(raw.substring('PDF generation failed: '.length)),
      });
    }

    if (raw.startsWith('Myanmar PDF font is missing.')) {
      return t('Myanmar PDF font is missing.') + raw.substring('Myanmar PDF font is missing.'.length);
    }

    if (raw.startsWith('Stored data could not be loaded safely: ')) {
      return t('Stored data could not be loaded safely: ') +
          UiTranslation.error(raw.substring('Stored data could not be loaded safely: '.length));
    }

    return t(raw);
  }

  /// Translate internally generated ledger/payment notes while leaving
  /// user-entered note text unchanged.
  static String note(String english) {
    final supply = RegExp(
      r'^(.+) • Qty (.+) • Total (.+) • Paid (.+)$',
    ).firstMatch(english);
    if (supply != null) {
      return f('{product} • Qty {qty} • Total {total} • Paid {paid}', {
        'product': supply.group(1)!,
        'qty': supply.group(2)!,
        'total': supply.group(3)!,
        'paid': supply.group(4)!,
      });
    }

    final voucher = RegExp(
      r'^Voucher (.+) • Paid (.+) / (.+)$',
    ).firstMatch(english);
    if (voucher != null) {
      return f('Voucher {voucher} • Paid {paid} / {total}', {
        'voucher': voucher.group(1)!,
        'paid': voucher.group(2)!,
        'total': voucher.group(3)!,
      });
    }

    final sale = RegExp(
      r'^Sale (.+?)(?: • (Cash|Bank|Mobile|Credit))?(?: • (.*))?$',
    ).firstMatch(english);
    if (sale != null) {
      var result = f('Sale {voucher}', {'voucher': sale.group(1)!});
      final method = sale.group(2);
      final extra = sale.group(3);
      if (method != null && method.isNotEmpty) {
        result += ' • ${t(method)}';
      }
      if (extra != null && extra.isNotEmpty) {
        result += ' • $extra';
      }
      return result;
    }

    final purchase = RegExp(
      r'^Purchase (.+?)(?: • (Cash|Bank|Mobile|Credit))?(?: • (.*))?$',
    ).firstMatch(english);
    if (purchase != null) {
      var result = f('Purchase {product}', {'product': purchase.group(1)!});
      final method = purchase.group(2);
      final extra = purchase.group(3);
      if (method != null && method.isNotEmpty) {
        result += ' • ${t(method)}';
      }
      if (extra != null && extra.isNotEmpty) {
        result += ' • $extra';
      }
      return result;
    }

    return t(english);
  }

  static String t(String english) {
    if (!isBurmese) return english;

    // These messages contain a runtime character count, so they cannot be
    // stored as interpolated keys in the const translation map.
    if (english.startsWith('Backup copied (') &&
        english.endsWith(' characters). For large backups, save it as a file instead of using the clipboard.')) {
      return 'အရန်ဒေတာကို ကူးယူပြီးပါပြီ။ ဒေတာအများအပြားအတွက် Clipboard အစား ဖိုင်အဖြစ် သိမ်းဆည်းပါ။';
    }
    if (english.startsWith('Backup file saved (') && english.endsWith(' characters).')) {
      return 'အရန်ဒေတာဖိုင်ကို သိမ်းပြီးပါပြီ။';
    }

    return _my[english] ?? english;
  }

  static String f(String template, [Map<String, String> values = const {}]) {
    var result = t(template);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

String uiT(String english) => UiTranslation.t(english);

String uiF(String template, Map<String, String> values) =>
    UiTranslation.f(template, values);

String uiError(Object error) => UiTranslation.error(error);

String uiLedgerNote(String english) => UiTranslation.note(english);
