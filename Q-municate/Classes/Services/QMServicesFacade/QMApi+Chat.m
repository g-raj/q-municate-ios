//
//  QMApi+Messages.m
//  Q-municate
//
//  Created by Vitaliy Gorbachov on 9/24/15.
//  Copyright © 2015 Quickblox. All rights reserved.
//

#import "QMApi.h"
#import "QMSettingsManager.h"
#import "QMApi+Notifications.m"
#import "QMContentService.h"
#import "QMAVCallManager.h"
#import "QMChatUtils.h"

@implementation QMApi (Chat)

/**
 *  Messages
 */

#pragma mark - Messages

- (void)connectChat:(void(^)(BOOL success))block {
    [self.chatService connectWithCompletionBlock:^(NSError * _Nullable error) {
        //
        if (error != nil) {
            block(YES);
        }
        else {
            block(NO);
        }
    }];
}

- (void)disconnectFromChat {
    __weak __typeof(self)weakSelf = self;
    [self.chatService disconnectWithCompletionBlock:^(NSError * _Nullable error) {
        //
        if (error == nil) {
            [weakSelf.settingsManager setLastActivityDate:[NSDate date]];
        }
    }];
}

- (void)disconnectFromChatIfNeeded {
    
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground && !self.avCallManager.hasActiveCall && [[QBChat instance] isConnected]) {
        [self disconnectFromChat];
    }
}

/**
 *  ChatDialog
 */

#pragma mark - ChatDialog

- (void)fetchAllDialogs:(void(^)(void))completion {

    __weak __typeof(self)weakSelf = self;
    if (self.settingsManager.lastActivityDate != nil) {
        [self.chatService fetchDialogsUpdatedFromDate:self.settingsManager.lastActivityDate andPageLimit:kQMDialogsPageLimit iterationBlock:^(QBResponse *response, NSArray *dialogObjects, NSSet *dialogsUsersIDs, BOOL *stop) {
            //
            [weakSelf.usersService getUsersWithIDs:[dialogsUsersIDs allObjects]];
        } completionBlock:^(QBResponse *response) {
            //
            if (weakSelf.isAuthorized && response.success) weakSelf.settingsManager.lastActivityDate = [NSDate date];
            if (completion) completion();
        }];
    }
    else {
        [self.chatService allDialogsWithPageLimit:kQMDialogsPageLimit extendedRequest:nil iterationBlock:^(QBResponse *response, NSArray *dialogObjects, NSSet *dialogsUsersIDs, BOOL *stop) {
            //
            [weakSelf.usersService getUsersWithIDs:[dialogsUsersIDs allObjects]];
        } completion:^(QBResponse *response) {
            //
            if (weakSelf.isAuthorized && response.success) weakSelf.settingsManager.lastActivityDate = [NSDate date];
            if (completion) completion();
        }];
    }
}

#pragma mark - Create Chat Dialogs

- (void)createGroupChatDialogWithName:(NSString *)name occupants:(NSArray *)occupants completion:(void(^)(QBChatDialog *chatDialog))completion {
    
    __weak typeof(self)weakSelf = self;
    [[self.chatService createGroupChatDialogWithName:name photo:nil occupants:occupants] continueWithBlock:^id _Nullable(BFTask<QBChatDialog *> * _Nonnull task) {
        //
        if (task.error != nil) {
            
            if (completion) completion(nil);
        } else {
            
            __typeof(weakSelf)strongSelf = weakSelf;
            NSArray *occupantsIDs = [strongSelf idsWithUsers:occupants];
            
            [strongSelf.chatService sendSystemMessageAboutAddingToDialog:task.result toUsersIDs:occupantsIDs completion:^(NSError *systemMessageError) {
                //
                [strongSelf.chatService sendNotificationMessageAboutAddingOccupants:occupantsIDs
                                                                           toDialog:task.result
                                                               withNotificationText:kDialogsUpdateNotificationMessage
                                                                         completion:^(NSError *error) {
                                                                             //
                                                                             if (completion) completion(task.result);
                                                                         }];
            }];
            
        }
        
        return nil;
    }];
}


#pragma mark - Edit dialog methods

- (void)changeChatName:(NSString *)dialogName forChatDialog:(QBChatDialog *)chatDialog completion:(void (^)(QBChatDialog *updatedDialog))completion {
    
    __weak __typeof(self)weakSelf = self;
    [[self.chatService changeDialogName:dialogName forChatDialog:chatDialog] continueWithBlock:^id _Nullable(BFTask<QBChatDialog *> * _Nonnull task) {
        //
        if (task.error != nil) {
            if (completion) completion(nil);
        } else {
            [weakSelf.chatService sendNotificationMessageAboutChangingDialogName:task.result
                                                            withNotificationText:kDialogsUpdateNotificationMessage
                                                                      completion:^(NSError * _Nullable error) {
                                                                          //
                                                                      }];
            if (completion) completion(task.result);
        }
        
        return nil;
    }];
}

- (void)changeAvatar:(UIImage *)avatar forChatDialog:(QBChatDialog *)chatDialog completion:(void(^)(QBChatDialog *updatedDialog))completion
{
    __weak typeof(self)weakSelf = self;
    [self.contentService uploadPNGImage:avatar progress:^(float progress) {
        //
    } completion:^(QBResponse *response, QBCBlob *blob) {
        //
        // update chat dialog:
        if (!response.success) {
            return;
        }
        
        __typeof(weakSelf)strongSelf = weakSelf;
        [[strongSelf.chatService changeDialogAvatar:blob.publicUrl forChatDialog:chatDialog] continueWithBlock:^id _Nullable(BFTask<QBChatDialog *> * _Nonnull task) {
            //
            if (task.error != nil) {
                if (completion) completion(nil);
            } else {
                [strongSelf.chatService sendNotificationMessageAboutChangingDialogPhoto:task.result
                                                                   withNotificationText:kDialogsUpdateNotificationMessage
                                                                             completion:^(NSError * _Nullable error) {
                                                                                 //
                                                                             }];
                if (completion) completion(task.result);
            }
            
            return nil;
        }];
    }];
}

- (void)joinOccupants:(NSArray *)occupants toChatDialog:(QBChatDialog *)chatDialog completion:(void(^)(QBChatDialog *updatedDialog))completion {
    
    NSArray *occupantsToJoinIDs = [self idsWithUsers:occupants];
    
    __weak __typeof(self)weakSelf = self;
    [[self.chatService joinOccupantsWithIDs:occupantsToJoinIDs toChatDialog:chatDialog] continueWithBlock:^id _Nullable(BFTask<QBChatDialog *> * _Nonnull task) {
        //
        if (task.error != nil) {
            if (completion) completion(nil);
        } else {
            
            __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf.chatService sendSystemMessageAboutAddingToDialog:chatDialog toUsersIDs:occupantsToJoinIDs completion:^(NSError * _Nullable systemMessageError) {
                //
                [strongSelf.chatService sendNotificationMessageAboutAddingOccupants:occupantsToJoinIDs
                                                                           toDialog:task.result
                                                               withNotificationText:kDialogsUpdateNotificationMessage
                                                                         completion:^(NSError * _Nullable error) {
                                                                             //
                                                                         }];
                if (completion) completion(task.result);
            }];
        }
        
        return nil;
    }];
}

- (void)leaveChatDialog:(QBChatDialog *)chatDialog completion:(QBChatCompletionBlock)completion {
    
    __weak __typeof(self)weakSelf = self;
    [self.chatService sendNotificationMessageAboutLeavingDialog:chatDialog
                                           withNotificationText:kDialogsUpdateNotificationMessage
                                                     completion:^(NSError * _Nullable error) {
                                                         //
                                                         if (error == nil) {
                                                             [weakSelf.chatService deleteDialogWithID:chatDialog.ID completion:^(QBResponse *response) {
                                                                 //
                                                                 if (completion) completion(response.error.error);
                                                             }];
                                                         } else {
                                                             if (completion) completion(error);
                                                         }
                                                     }];
}

- (NSUInteger )occupantIDForPrivateChatDialog:(QBChatDialog *)chatDialog {
    
    NSAssert(chatDialog.type == QBChatDialogTypePrivate, @"Chat dialog type != QBChatDialogTypePrivate");
    
    NSInteger myID = self.currentUser.ID;
    
    for (NSNumber *ID in chatDialog.occupantIDs) {
        
        if (ID.integerValue != myID) {
            return ID.integerValue;
        }
    }
    
    NSAssert(nil, @"Need update this case");
    return 0;
}

- (void)deleteChatDialog:(QBChatDialog *)dialog completion:(void(^)(BOOL success))completionHandler
{
    [self.chatService deleteDialogWithID:dialog.ID completion:^(QBResponse *response) {
        //
        if (completionHandler) completionHandler(response.success);
    }];
}

#pragma mark - Dialogs toos

- (NSArray *)dialogHistory {
    return [self.chatService.dialogsMemoryStorage unsortedDialogs];
}

- (QBChatDialog *)chatDialogWithID:(NSString *)dialogID {
    
    return [self.chatService.dialogsMemoryStorage chatDialogWithID:dialogID];
}

- (NSArray *)allOccupantIDsFromDialogsHistory{
    
    NSArray *allDialogs = [self.chatService.dialogsMemoryStorage unsortedDialogs];
    NSMutableSet *ids = [NSMutableSet set];
    
    for (QBChatDialog *dialog in allDialogs) {
        [ids addObjectsFromArray:dialog.occupantIDs];
    }
    
    return ids.allObjects;
}

@end
