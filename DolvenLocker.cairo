#       ___       __                __        __
#      / _ \___  / /  _____ ___    / /  ___ _/ /  ___
#     / // / _ \/ / |/ / -_) _ \  / /__/ _ `/ _ \(_-<
#    /____/\___/_/|___/\__/_//_/ /____/\_,_/_.__/___/

# Time Locker Contract for StarkNet

%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
    get_block_timestamp,
)
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_sub,
    uint256_le,
    uint256_lt,
    uint256_check,
    uint256_eq,
    uint256_mul,
    uint256_unsigned_div_rem,
)

from starkware.cairo.common.math import (
    unsigned_div_rem,
    assert_not_zero,
    assert_not_equal,
    assert_nn,
    assert_le,
    assert_lt,
    assert_nn_le,
    assert_in_range,
)

struct Lock_Info:
    member nonce : felt
    member start_date : felt
    member end_date : felt
    member amount : felt
    member token_address : felt
    member manager_address : felt
    member is_unlocked : felt
end

@event
func locked(
    nonce : felt,
    start_date : felt,
    end_date : felt,
    amount : felt,
    token_address : felt,
    manager_address : felt,
):
end

@event
func locked_more_tokens(nonce : felt, timestamp : felt, token_address : felt, amount : felt):
end

@event
func lock_time_increased(
    nonce : felt, timestamp : felt, token_address : felt, increase_time : felt
):
end

@event
func unlocked(
    nonce : felt,
    start_date : felt,
    end_date : felt,
    unlock_date : felt,
    amount : felt,
    token_address : felt,
    manager_address : felt,
):
end

@event
func transfered_lock_ownable(
    nonce : felt, timestamp : felt, old_manager_address : felt, manager_address : felt
):
end

@storage_var
func manager() -> (user : felt):
end

@storage_var
func nonce() -> (nonce : felt):
end

@storage_var
func locks(nonce : felt) -> (lock : Lock_Info):
end

@storage_var
func user_nonces(user_address : felt, user_nonce_index : felt) -> (nonce : felt):
end

@storage_var
func user_lock_count(user_address : felt) -> (count : felt):
end

@external
func lock_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    end_date : felt, amount : felt, token_address : felt, manager_address : felt
):
    alloc_locals
    let (caller) = get_caller_address()
    let (pool_manager) = get_pool_manager(manager_address, caller)
    let (timestamp) = get_block_timestamp()
    let (old_nonce) = nonce.read()
    let (lock_count) = user_lock_count.read(pool_manager)
    with_attr error_message("Current timestamp must be lower than end date. Got: {end_date}."):
        assert_lt(timestamp, end_date)
    end
    with_attr error_message("Amount must be positive. Got: {amount}."):
        assert_nn(amount)
    end
    with_attr error_message("pool_manager must be nonzero. Got: {pool_manager}."):
        assert_not_zero(pool_manager)
    end
    with_attr error_message("token_address must be nonzero. Got: {token_address}."):
        assert_not_zero(token_address)
    end
    # todo
    # add erc20 transferfrom caller to this contract
    let lock_instance = Lock_Info(
        old_nonce, timestamp, end_date, amount, token_address, pool_manager, 0
    )
    nonce.write(old_nonce + 1)
    locks.write(old_nonce, lock_instance)
    user_nonces.write(pool_manager, lock_count, old_nonce)
    user_lock_count.write(pool_manager, lock_count + 1)
    locked.emit(old_nonce, timestamp, end_date, amount, token_address, pool_manager)
    return ()
end

func get_pool_manager{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    manager_address : felt, caller : felt
) -> (res : felt):
    if manager_address == 0:
        return (caller)
    else:
        return (manager_address)
    end
end

@view
func get_lock_info{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    nonce : felt
) -> (res : Lock_Info):
    let (lock : Lock_Info) = locks.read(nonce)
    return (lock)
end

@view
func get_user_locks{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user_address : felt
) -> (user_locks_len : felt, user_locks : Lock_Info*):
    alloc_locals
    let (lock_count) = user_lock_count.read(user_address)
    let (user_locks_memory_loc) = _get_user_locks(user_address, 0, lock_count)
    let user_locks : Lock_Info* = user_locks_memory_loc - lock_count * Lock_Info.SIZE
    return (lock_count, user_locks)
end

func _get_user_locks{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user_address : felt, nonce_index : felt, lock_count : felt
) -> (user_locks_memory_loc : Lock_Info*):
    alloc_locals
    let (nonce) = user_nonces.read(user_address, nonce_index)
    if nonce_index == lock_count:
        let (found_locks : Lock_Info*) = alloc()
        return (found_locks)
    end
    let lock : Lock_Info = locks.read(nonce)

    let (user_locks_memory_loc) = _get_user_locks(user_address, nonce_index + 1, lock_count)
    assert [user_locks_memory_loc] = lock
    return (user_locks_memory_loc + Lock_Info.SIZE)
end

@external
func unlock_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(nonce : felt):
    alloc_locals
    let (caller) = get_caller_address()

    with_attr error_message("caller must be nonzero. Got: {caller}."):
        assert_not_zero(caller)
    end
    let (lock : Lock_Info) = locks.read(nonce)
    with_attr error_message("caller must be equal pool manager. Got: {lock.pool_manager}."):
        assert_not_equal(caller, lock.manager_address)
    end
    with_attr error_message("lock must be unlocked. Got: {lock.is_unlocked}."):
        assert_not_zero(lock.is_unlocked)
    end
    let (timestamp) = get_block_timestamp()
    with_attr error_message("Lock timestamp must be lower than now. Got: {lock.end_date}."):
        assert_lt(lock.end_date, timestamp)
    end
    # todo
    # add erc20 transfer tokens contract to caller
    let lock_instance = Lock_Info(
        lock.nonce, lock.start_date, lock.end_date, 0, lock.token_address, lock.manager_address, 1
    )
    unlocked.emit(
        lock.nonce,
        lock.start_date,
        lock.end_date,
        timestamp,
        lock.amount,
        lock.token_address,
        lock.manager_address,
    )
    locks.write(lock.nonce, lock_instance)
    return ()
end

@external
func lock_more_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    nonce : felt, amount : felt
):
    alloc_locals
    let (caller) = get_caller_address()
    let (lock : Lock_Info) = locks.read(nonce)
    with_attr error_message("caller must be equal pool manager. Got: {lock.pool_manager}."):
        assert_not_equal(caller, lock.manager_address)
    end
    let (timestamp) = get_block_timestamp()
    with_attr error_message("Timestamp must be lower than lock end date. Got: {lock.end_date}."):
        assert_lt(timestamp, lock.end_date)
    end
    with_attr error_message("Amount must be positive. Got: {amount}."):
        assert_nn(amount)
    end
    with_attr error_message("caller must be nonzero. Got: {caller}."):
        assert_not_zero(caller)
    end
    # todo
    # add erc20 transferfrom caller to this contract
    let lock_instance = Lock_Info(
        lock.nonce,
        lock.start_date,
        lock.end_date,
        lock.amount + amount,
        lock.token_address,
        lock.manager_address,
        0,
    )
    locked_more_tokens.emit(lock.nonce, timestamp, lock.token_address, amount)
    locks.write(lock.nonce, lock_instance)
    return ()
end

@external
func increase_lock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    nonce : felt, time : felt
):
    alloc_locals
    let (caller) = get_caller_address()
    let (lock : Lock_Info) = locks.read(nonce)
    let (timestamp) = get_block_timestamp()
    with_attr error_message("caller must be equal pool manager. Got: {lock.pool_manager}."):
        assert_not_equal(caller, lock.manager_address)
    end
    with_attr error_message("Time must be positive. Got: {time}."):
        assert_nn(time)
    end
    with_attr error_message("caller must be nonzero. Got: {caller}."):
        assert_not_zero(caller)
    end

    let lock_instance = Lock_Info(
        lock.nonce,
        lock.start_date,
        lock.end_date + time,
        lock.amount,
        lock.token_address,
        lock.manager_address,
        0,
    )
    lock_time_increased.emit(lock.nonce, timestamp, lock.token_address, time)
    locks.write(lock.nonce, lock_instance)
    return ()
end

@external
func transfer_lock_ownable{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    nonce : felt, new_manager_address : felt
):
    alloc_locals
    let (caller) = get_caller_address()
    with_attr error_message("caller must be nonzero. Got: {caller}."):
        assert_not_zero(caller)
    end
    let (lock : Lock_Info) = locks.read(nonce)
    with_attr error_message("caller must be equal pool manager. Got: {lock.pool_manager}."):
        assert_not_equal(caller, lock.manager_address)
    end
    let (timestamp) = get_block_timestamp()
    with_attr error_message("Timestamp must be lower than lock end date. Got: {lock.end_date}."):
        assert_lt(timestamp, lock.end_date)
    end
    # todo
    # add erc20 transfer tokens contract to caller
    let lock_instance = Lock_Info(
        lock.nonce, lock.start_date, lock.end_date, 0, lock.token_address, new_manager_address, 1
    )
    transfered_lock_ownable.emit(lock.nonce, timestamp, lock.manager_address, new_manager_address)
    locks.write(lock.nonce, lock_instance)
    return ()
end

