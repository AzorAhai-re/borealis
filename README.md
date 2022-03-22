# borealis
Upcoming Tokenomics Project ~ Blockchain SLU

This project will hold the Smart Contracts and [Hardhat](https://hardhat.org/) sub-project for Borealis.

## requirements
* [NodeJS](https://nodejs.org/en/download/package-manager/)
* A text editor, I use [VSCode](https://code.visualstudio.com/) but [Sublime](https://www.sublimetext.com/) and vim are pretty tight too.

## installation
Clone this project
```bash
git clone https://github.com/AzorAhai-re/borealis.git
cd borealis
```

Install hardhat and its dependencies
```bash
npm i
```

## testing
Tests are located in `./test`. If you'd like to edit these tests you can go there and do as you like.

If you'd like to run tests simply run
```bash
npx hardhat test
```
If you'd like to only test one function then add a `.only` in behind of the test section declarations (statements that start with `describe`) and/or individual tests (statements that start with `it`).
