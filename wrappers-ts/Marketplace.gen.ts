// AUTO-GENERATED, do not edit
// It's a TypeScript wrapper for a Marketplace contract in Tolk.
/* eslint-disable */

import * as c from '@ton/core';
import { beginCell, ContractProvider, Sender, SendMode } from '@ton/core';

// ————————————————————————————————————————————
//   predefined types and functions
//

type StoreCallback<T> = (obj: T, b: c.Builder) => void
type LoadCallback<T> = (s: c.Slice) => T

export type CellRef<T> = {
    ref: T
}

function makeCellFrom<T>(self: T, storeFn_T: StoreCallback<T>): c.Cell {
    let b = beginCell();
    storeFn_T(self, b);
    return b.endCell();
}

function loadAndCheckPrefix32(s: c.Slice, expected: number, structName: string): void {
    let prefix = s.loadUint(32);
    if (prefix !== expected) {
        throw new Error(`Incorrect prefix for '${structName}': expected 0x${expected.toString(16).padStart(8, '0')}, got 0x${prefix.toString(16).padStart(8, '0')}`);
    }
}

function lookupPrefix(s: c.Slice, expected: number, prefixLen: number): boolean {
    return s.remainingBits >= prefixLen && s.preloadUint(prefixLen) === expected;
}

function throwNonePrefixMatch(fieldPath: string): never {
    throw new Error(`Incorrect prefix for '${fieldPath}': none of variants matched`);
}

function storeCellRef<T>(cell: CellRef<T>, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    let b_ref = c.beginCell();
    storeFn_T(cell.ref, b_ref);
    b.storeRef(b_ref.endCell());
}

function loadCellRef<T>(s: c.Slice, loadFn_T: LoadCallback<T>): CellRef<T> {
    let s_ref = s.loadRef().beginParse();
    return { ref: loadFn_T(s_ref) };
}

function storeTolkNullable<T>(v: T | null, b: c.Builder, storeFn_T: StoreCallback<T>): void {
    if (v === null) {
        b.storeUint(0, 1);
    } else {
        b.storeUint(1, 1);
        storeFn_T(v, b);
    }
}

// ————————————————————————————————————————————
//   parse get methods result from a TVM stack
//

class StackReader {
    constructor(private tuple: c.TupleItem[]) {
    }

    static fromGetMethod(expectedN: number, getMethodResult: { stack: c.TupleReader }): StackReader {
        let tuple = [] as c.TupleItem[];
        while (getMethodResult.stack.remaining) {
            tuple.push(getMethodResult.stack.pop());
        }
        if (tuple.length !== expectedN) {
            throw new Error(`expected ${expectedN} stack width, got ${tuple.length}`);
        }
        return new StackReader(tuple);
    }

    private popExpecting<ItemT>(itemType: string): ItemT {
        const item = this.tuple.shift();
        if (item?.type === itemType) {
            return item as ItemT;
        }
        throw new Error(`not '${itemType}' on a stack`);
    }

    private popCellLike(): c.Cell {
        const item = this.tuple.shift();
        if (item && (item.type === 'cell' || item.type === 'slice' || item.type === 'builder')) {
            return item.cell;
        }
        throw new Error(`not cell/slice on a stack`);
    }

    readBigInt(): bigint {
        return this.popExpecting<c.TupleItemInt>('int').value;
    }

    readBoolean(): boolean {
        return this.popExpecting<c.TupleItemInt>('int').value !== 0n;
    }

    readCell(): c.Cell {
        return this.popCellLike();
    }

    readSlice(): c.Slice {
        return this.popCellLike().beginParse();
    }
}

// ————————————————————————————————————————————
//   auto-generated serializers to/from cells
//

type coins = bigint

type uint32 = bigint
type uint64 = bigint

/**
 > struct MarketplaceStorage {
 >     owner: address
 >     orderCode: cell
 >     orderCount: uint32
 > }
 */
export interface MarketplaceStorage {
    readonly $: 'MarketplaceStorage'
    owner: c.Address
    orderCode: c.Cell
    orderCount: uint32
}

export const MarketplaceStorage = {
    create(args: {
        owner: c.Address
        orderCode: c.Cell
        orderCount: uint32
    }): MarketplaceStorage {
        return {
            $: 'MarketplaceStorage',
            ...args
        }
    },
    fromSlice(s: c.Slice): MarketplaceStorage {
        return {
            $: 'MarketplaceStorage',
            owner: s.loadAddress(),
            orderCode: s.loadRef(),
            orderCount: s.loadUintBig(32),
        }
    },
    store(self: MarketplaceStorage, b: c.Builder): void {
        b.storeAddress(self.owner);
        b.storeRef(self.orderCode);
        b.storeUint(self.orderCount, 32);
    },
    toCell(self: MarketplaceStorage): c.Cell {
        return makeCellFrom<MarketplaceStorage>(self, MarketplaceStorage.store);
    }
}

/**
 > struct (0xa00a0000) CreateOrder {
 >     reward: coins
 >     nonce: uint64
 >     createdAt: uint32
 >     description: cell
 >     area: cell
 >     senderContact: cell
 > }
 */
export interface CreateOrder {
    readonly $: 'CreateOrder'
    reward: coins
    nonce: uint64
    createdAt: uint32
    description: c.Cell
    area: c.Cell
    senderContact: c.Cell
}

export const CreateOrder = {
    PREFIX: 0xa00a0000,

    create(args: {
        reward: coins
        nonce: uint64
        createdAt: uint32
        description: c.Cell
        area: c.Cell
        senderContact: c.Cell
    }): CreateOrder {
        return {
            $: 'CreateOrder',
            ...args
        }
    },
    fromSlice(s: c.Slice): CreateOrder {
        loadAndCheckPrefix32(s, 0xa00a0000, 'CreateOrder');
        return {
            $: 'CreateOrder',
            reward: s.loadCoins(),
            nonce: s.loadUintBig(64),
            createdAt: s.loadUintBig(32),
            description: s.loadRef(),
            area: s.loadRef(),
            senderContact: s.loadRef(),
        }
    },
    store(self: CreateOrder, b: c.Builder): void {
        b.storeUint(0xa00a0000, 32);
        b.storeCoins(self.reward);
        b.storeUint(self.nonce, 64);
        b.storeUint(self.createdAt, 32);
        b.storeRef(self.description);
        b.storeRef(self.area);
        b.storeRef(self.senderContact);
    },
    toCell(self: CreateOrder): c.Cell {
        return makeCellFrom<CreateOrder>(self, CreateOrder.store);
    }
}

/**
 > type MarketplaceMessage = CreateOrder
 */
export type MarketplaceMessage = CreateOrder

export const MarketplaceMessage = {
    fromSlice(s: c.Slice): MarketplaceMessage {
        return CreateOrder.fromSlice(s);
    },
    store(self: MarketplaceMessage, b: c.Builder): void {
        CreateOrder.store(self, b);
    },
    toCell(self: MarketplaceMessage): c.Cell {
        return makeCellFrom<MarketplaceMessage>(self, MarketplaceMessage.store);
    }
}

// ————————————————————————————————————————————
//    class Marketplace
//

interface ExtraSendOptions {
    bounce?: boolean                    // default: false
    sendMode?: SendMode                 // default: SendMode.PAY_GAS_SEPARATELY
    extraCurrencies?: c.ExtraCurrency   // default: empty dict
}

interface DeployedAddrOptions {
    workchain?: number                  // default: 0 (basechain)
    toShard?: { fixedPrefixLength: number; closeTo: c.Address }
    overrideContractCode?: c.Cell
}

function calculateDeployedAddress(code: c.Cell, data: c.Cell, options: DeployedAddrOptions): c.Address {
    const stateInitCell = beginCell().store(c.storeStateInit({
        code,
        data,
        splitDepth: options.toShard?.fixedPrefixLength,
        special: null,
        libraries: null,
    })).endCell();

    let addrHash = stateInitCell.hash();
    if (options.toShard) {
        const shardDepth = options.toShard.fixedPrefixLength;
        addrHash = beginCell()
            .storeBits(new c.BitString(options.toShard.closeTo.hash, 0, shardDepth))
            .storeBits(new c.BitString(stateInitCell.hash(), shardDepth, 256 - shardDepth))
            .endCell()
            .beginParse().loadBuffer(32);
    }

    return new c.Address(options.workchain ?? 0, addrHash);
}

export class Marketplace implements c.Contract {
    static CodeCell = c.Cell.fromBase64('te6ccgECCgEAARoAART/APSkE/S88sgLAQIBYgIDAUbQ+JGRMOAg7UTQ+kjU1wsfA9csJQBQAATjAl8EhA8BxwDy9AQCASAFBgHiNAP6ANM/0x/U1NdM+Jcmggr68ICgvvLgyAekJsj6UinPFMsfye1U+JJtiAjI+lIZzBfMyQbI+lIX+lTMFcxY+gLPhALLPxLLH8+QAAAAAszJyM+JCAFTEsjPhNDMzPkWzwv/gQCMzwt0EszMyYBA+wAJABG+KO9qJofSQYQCAUgHCAGLtbq9qJofSRrpjbEAeR9KQpmCWZkhGR9KQl9KgnmZigCfQFnwgEJZZ/lj+fIAAAAAQlmZIDkZ8JoZmZ8i2RnxQAgZf/nqEAkAF7Q83aiaH0kGOuFj8AAA');

    static Errors = {
        'MarketplaceErrors.InsufficientValue': 200,
        'MarketplaceErrors.InvalidMessage': 65535,
    }

    readonly address: c.Address
    readonly init: { code: c.Cell, data: c.Cell } | undefined

    protected constructor(address: c.Address, init?: { code: c.Cell, data: c.Cell }) {
        this.address = address;
        this.init = init;
    }

    static fromAddress(address: c.Address) {
        return new Marketplace(address);
    }

    static fromStorage(emptyStorage: {
        owner: c.Address
        orderCode: c.Cell
        orderCount: uint32
    }, deployedOptions?: DeployedAddrOptions) {
        const initialState = {
            code: deployedOptions?.overrideContractCode ?? Marketplace.CodeCell,
            data: MarketplaceStorage.toCell(MarketplaceStorage.create(emptyStorage)),
        };
        const address = calculateDeployedAddress(initialState.code, initialState.data, deployedOptions ?? {});
        return new Marketplace(address, initialState);
    }

    static createCellOfMarketplaceMessage(body: MarketplaceMessage) {
        return MarketplaceMessage.toCell(body);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, msgValue: coins, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: c.Cell.EMPTY,
            ...extraOptions
        });
    }

    async sendMarketplaceMessage(provider: ContractProvider, via: Sender, msgValue: coins, body: MarketplaceMessage, extraOptions?: ExtraSendOptions) {
        return provider.internal(via, {
            value: msgValue,
            body: MarketplaceMessage.toCell(body),
            ...extraOptions
        });
    }

    async getOrderCount(provider: ContractProvider): Promise<uint32> {
        const r = StackReader.fromGetMethod(1, await provider.get('orderCount', []));
        return r.readBigInt();
    }

    async getOwner(provider: ContractProvider): Promise<c.Address> {
        const r = StackReader.fromGetMethod(1, await provider.get('owner', []));
        return r.readSlice().loadAddress();
    }

    async getOrderAddress(provider: ContractProvider, sender: c.Address, reward: coins, nonce: uint64, createdAt: uint32, description: c.Cell, area: c.Cell, senderContact: c.Cell): Promise<c.Address> {
        const r = StackReader.fromGetMethod(1, await provider.get('orderAddress', [
            { type: 'slice', cell: makeCellFrom<c.Address>(sender,
                (v,b) => b.storeAddress(v)
            ) },
            { type: 'int', value: reward },
            { type: 'int', value: nonce },
            { type: 'int', value: createdAt },
            { type: 'cell', cell: description },
            { type: 'cell', cell: area },
            { type: 'cell', cell: senderContact },
        ]));
        return r.readSlice().loadAddress();
    }
}
