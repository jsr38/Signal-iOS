//
//  RegistrationViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"


#import "Environment.h"
#import "LocalizableText.h"
#import "NBAsYouTypeFormatter.h"
#import "PhoneNumber.h"
#import "PhoneNumberDirectoryFilterManager.h"
#import "PhoneNumberUtil.h"
#import "PreferencesUtil.h"
#import "PushManager.h"
#import "RPServerRequestsManager.h"
#import "SignalUtil.h"
#import "SGNKeychainUtil.h"
#import "ThreadManager.h"
#import "Util.h"

#import <Pastelog.h>




@interface RegistrationViewController ()

@end

@implementation RegistrationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self populateDefaultCountryNameAndCode];
    [self initializeKeyboardHandlers];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Locale

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *cc = [NBPhoneNumberUtil.sharedInstance getCountryCodeForRegion:countryCode];
    
    _countryCodeLabel.text = [NSString stringWithFormat:@"%@%@",COUNTRY_CODE_PREFIX, cc];
    //_countryNameLabel.text = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    _countryNameLabel.text = @"United States";
}


#pragma mark - Actions

- (IBAction)sendCodeAction:(id)sender {
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _countryCodeLabel.text, _phoneNumberTextField.text];
    PhoneNumber* localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    if(localNumber==nil){ return; }
    
    [_phoneNumberTextField resignFirstResponder];
    
    // perform RPServerRequest here

    
}

- (IBAction)changeCountryCodeTapped {
    CountryCodeViewController *countryCodeController = [[CountryCodeViewController alloc] init];
    countryCodeController.delegate = self;
    [self presentViewController:countryCodeController animated:YES completion:nil];
}

- (void)presentInvalidCountryCodeError {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:REGISTER_CC_ERR_ALERT_VIEW_TITLE
                                                        message:REGISTER_CC_ERR_ALERT_VIEW_MESSAGE
                                                       delegate:nil
                                              cancelButtonTitle:REGISTER_CC_ERR_ALERT_VIEW_DISMISS
                                              otherButtonTitles:nil];
    [alertView show];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers{
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
    
    //[self observeKeyboardNotifications];
    
}

-(void) dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}


#pragma mark - CountryCodeViewControllerDelegate

- (void)countryCodeViewController:(CountryCodeViewController *)vc
             didSelectCountryCode:(NSString *)code
                       forCountry:(NSString *)country {
    
    //NOTE: It seems [PhoneNumberUtil countryNameFromCountryCode:] doesn't return the country at all. Will investigate.
    _countryCodeLabel.text = code;
    _countryNameLabel.text = country;
    
    // Reformat phone number
    NSString* digits = _phoneNumberTextField.text.digitsOnly;
    NSString* reformattedNumber = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:digits
                                                                               withSpecifiedCountryCodeString:_countryCodeLabel.text];
    _phoneNumberTextField.text = reformattedNumber;
    UITextPosition *pos = _phoneNumberTextField.endOfDocument;
    [_phoneNumberTextField setSelectedTextRange:[_phoneNumberTextField textRangeFromPosition:pos toPosition:pos]];
    
    // Done choosing country
    [vc dismissViewControllerAnimated:YES completion:nil];
}

- (void)countryCodeViewControllerDidCancel:(CountryCodeViewController *)vc {
    [vc dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITextFieldDelegate

-(BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString* textBeforeChange = textField.text;
    
    // backspacing should skip over formatting characters
    UITextPosition *posIfBackspace = [textField positionFromPosition:textField.beginningOfDocument
                                                              offset:(NSInteger)(range.location + range.length)];
    UITextRange *rangeIfBackspace = [textField textRangeFromPosition:posIfBackspace toPosition:posIfBackspace];
    bool isBackspace = string.length == 0 && range.length == 1 && [rangeIfBackspace isEqual:textField.selectedTextRange];
    if (isBackspace) {
        NSString* digits = textBeforeChange.digitsOnly;
        NSUInteger correspondingDeletePosition = [PhoneNumberUtil translateCursorPosition:range.location + range.length
                                                                                     from:textBeforeChange
                                                                                       to:digits
                                                                        stickingRightward:true];
        if (correspondingDeletePosition > 0) {
            textBeforeChange = digits;
            range = NSMakeRange(correspondingDeletePosition - 1, 1);
        }
    }
    
    // make the proposed change
    NSString* textAfterChange = [textBeforeChange withCharactersInRange:range replacedBy:string];
    NSUInteger cursorPositionAfterChange = range.location + string.length;
    
    // reformat the phone number, trying to keep the cursor beside the inserted or deleted digit
    bool isJustDeletion = string.length == 0;
    NSString* textAfterReformat = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:textAfterChange.digitsOnly
                                                                               withSpecifiedCountryCodeString:_countryCodeLabel.text];
    NSUInteger cursorPositionAfterReformat = [PhoneNumberUtil translateCursorPosition:cursorPositionAfterChange
                                                                                 from:textAfterChange
                                                                                   to:textAfterReformat
                                                                    stickingRightward:isJustDeletion];
    textField.text = textAfterReformat;
    UITextPosition *pos = [textField positionFromPosition:textField.beginningOfDocument
                                                   offset:(NSInteger)cursorPositionAfterReformat];
    [textField setSelectedTextRange:[textField textRangeFromPosition:pos toPosition:pos]];
    
    return NO; // inform our caller that we took care of performing the change
}


/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
