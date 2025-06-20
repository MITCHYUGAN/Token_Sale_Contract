use core::num::traits::Zero;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, get_class_hash
};
use starknet::{ClassHash, ContractAddress};
use token_sale_contract::interfaces::itoken_sale::{ITokenSaleDispatcher, ITokenSaleDispatcherTrait};

// Constants for Sepolia testnet token addresses
const ACCEPTED_PAYMENT_TOKEN: ContractAddress =
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7
    .try_into()
    .unwrap(); // ETH token on Sepolia

const TOKEN_TO_BUY: ContractAddress =
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
    .try_into()
    .unwrap(); // STRK token on Sepolia

const OWNER: ContractAddress = 0x007e9244c7986db5e807d8838bcc218cd80ad4a82eb8fd1746e63fe223f67411
    .try_into()
    .unwrap();

const NON_OWNER_WITH_BALANCE: ContractAddress =
    0x000ed03da7bc876b74d81fe91564f8c9935a2ad2e1a842a822b4909203c8e796
    .try_into()
    .unwrap();

const NON_OWNER_WITHOUT_BALANCE: ContractAddress = 0x789.try_into().unwrap();

const PRICE: u256 = 21000;
const DEPOSIT_AMOUNT: u256 = 500;
const BUY_AMOUNT: u256 = 500;

// Helper function to deploy the TokenSale contract
fn deploy_token_sale_contract() -> (ITokenSaleDispatcher, IERC20Dispatcher, IERC20Dispatcher) {
    let contract = declare("TokenSale").unwrap();
    let mut constructor_args = array![];
    Serde::serialize(@OWNER, ref constructor_args);
    Serde::serialize(@ACCEPTED_PAYMENT_TOKEN, ref constructor_args);

    let (contract_address, _) = contract.contract_class().deploy(@constructor_args).unwrap();
    let token_sale_dispatcher = ITokenSaleDispatcher { contract_address };
    let eth_dispatcher = IERC20Dispatcher { contract_address: ACCEPTED_PAYMENT_TOKEN };
    let strk_dispatcher = IERC20Dispatcher { contract_address: TOKEN_TO_BUY };

    (token_sale_dispatcher, eth_dispatcher, strk_dispatcher)
}

// Unit test: Verify contract deployment
#[test]
fn test_constructor_initializes_state() {
    let (dispatcher, _, _) = deploy_token_sale_contract();
    assert(dispatcher.contract_address.is_non_zero(), 'Deployment failed');
}

// Unit test: Check available tokens (initially zero)
#[test]
fn test_check_available_token_initially_zero() {
    let (dispatcher, _, _) = deploy_token_sale_contract();
    let available = dispatcher.check_available_token(TOKEN_TO_BUY);
    assert(available == 0, 'Initial token balance must be 0');
}

// Integration test: Deposit token should fail if caller is not owner
#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: ('Unauthorized',))]
fn test_deposit_token_non_owner() {
    let (dispatcher, _, _) = deploy_token_sale_contract();
    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);
    dispatcher.deposit_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT, PRICE);
    stop_cheat_caller_address(dispatcher.contract_address);
}

// Integration test: Successful deposit by owner
#[test]
#[fork("SEPOLIA_LATEST")]
fn test_deposit_token_success() {
    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    // Approve token transfer
    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);
    strk_dispatcher.approve(dispatcher.contract_address, DEPOSIT_AMOUNT);
    stop_cheat_caller_address(strk_dispatcher.contract_address);

    // Deposit tokens
    start_cheat_caller_address(dispatcher.contract_address, OWNER);
    let contract_balance_before = strk_dispatcher.balance_of(dispatcher.contract_address);
    dispatcher.deposit_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT, PRICE);
    stop_cheat_caller_address(dispatcher.contract_address);

    // Verify state
    let contract_balance_after = strk_dispatcher.balance_of(dispatcher.contract_address);
    let available_tokens = dispatcher.check_available_token(TOKEN_TO_BUY);
    assert(contract_balance_after == contract_balance_before + DEPOSIT_AMOUNT, 'Incorrect balance');
    assert(available_tokens == DEPOSIT_AMOUNT, 'Incorrect available tokens');
}

// Integration test: Buy token should fail if amount is incorrect
#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: ('amount must be exact',))]
fn test_buy_token_incorrect_amount() {
    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    // Deposit tokens by owner
    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);
    strk_dispatcher.approve(dispatcher.contract_address, DEPOSIT_AMOUNT);
    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);
    dispatcher.deposit_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT, PRICE);
    stop_cheat_caller_address(dispatcher.contract_address);

    // Attempt to buy with incorrect amount
    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);
    dispatcher.buy_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT + 1);
    stop_cheat_caller_address(dispatcher.contract_address);
}

// Integration test: Buy token should fail if buyer has insufficient funds
#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: ('Insufficient funds',))]
fn test_buy_token_insufficient_funds() {
    let (dispatcher, _, strk_dispatcher) = deploy_token_sale_contract();

    // Deposit tokens by owner
    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);
    strk_dispatcher.approve(dispatcher.contract_address, DEPOSIT_AMOUNT);
    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);
    dispatcher.deposit_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT, PRICE);
    stop_cheat_caller_address(dispatcher.contract_address);

    // Attempt to buy with insufficient funds
    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITHOUT_BALANCE);
    dispatcher.buy_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT);
    stop_cheat_caller_address(dispatcher.contract_address);
}

// Integration test: Successful token purchase
#[test]
#[fork("SEPOLIA_LATEST")]
fn test_buy_token_success() {
    let (dispatcher, eth_dispatcher, strk_dispatcher) = deploy_token_sale_contract();

    // Deposit tokens by owner
    start_cheat_caller_address(strk_dispatcher.contract_address, OWNER);
    strk_dispatcher.approve(dispatcher.contract_address, DEPOSIT_AMOUNT);
    stop_cheat_caller_address(strk_dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, OWNER);
    dispatcher.deposit_token(TOKEN_TO_BUY, DEPOSIT_AMOUNT, PRICE);
    stop_cheat_caller_address(dispatcher.contract_address);

    // Approve payment token transfer by buyer
    start_cheat_caller_address(eth_dispatcher.contract_address, NON_OWNER_WITH_BALANCE);
    eth_dispatcher.approve(dispatcher.contract_address, PRICE);
    stop_cheat_caller_address(eth_dispatcher.contract_address);

    // Buy tokens
    let buyer_eth_before = eth_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let buyer_strk_before = strk_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let contract_eth_before = eth_dispatcher.balance_of(dispatcher.contract_address);
    let contract_strk_before = strk_dispatcher.balance_of(dispatcher.contract_address);

    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);
    dispatcher.buy_token(TOKEN_TO_BUY, BUY_AMOUNT);
    stop_cheat_caller_address(dispatcher.contract_address);

    // Verify balances
    let buyer_eth_after = eth_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let buyer_strk_after = strk_dispatcher.balance_of(NON_OWNER_WITH_BALANCE);
    let contract_eth_after = eth_dispatcher.balance_of(dispatcher.contract_address);
    let contract_strk_after = strk_dispatcher.balance_of(dispatcher.contract_address);

    assert(buyer_eth_after == buyer_eth_before - PRICE, 'Incorrect ETH balance');
    assert(buyer_strk_after == buyer_strk_before + BUY_AMOUNT, 'Incorrect STRK balance');
    assert(contract_eth_after == contract_eth_before + PRICE, 'Incorrect contract ETH');
    assert(contract_strk_after == contract_strk_before - BUY_AMOUNT, 'Incorrect contract STRK');
}

// Integration test: Upgrade should fail if caller is not owner
#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_non_owner() {
    let (dispatcher, _, _) = deploy_token_sale_contract();
    let new_class_hash: ClassHash = 112233.try_into().unwrap();
    start_cheat_caller_address(dispatcher.contract_address, NON_OWNER_WITH_BALANCE);
    dispatcher.upgrade(new_class_hash);
    stop_cheat_caller_address(dispatcher.contract_address);
}

// Unit test: Successful upgrade by owner
#[test]
fn test_upgrade_success() {
    let (dispatcher, _, _) = deploy_token_sale_contract();
    let new_class_hash: ClassHash = *declare("TokenSale").unwrap().contract_class().class_hash;

    start_cheat_caller_address(dispatcher.contract_address, OWNER);
    dispatcher.upgrade(new_class_hash);
    stop_cheat_caller_address(dispatcher.contract_address);

    let class_hash = get_class_hash(dispatcher.contract_address);
    assert(class_hash == new_class_hash, 'Class hash not updated');
}