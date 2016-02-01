contract EarthLottery{
  address minter;

  uint16 exponent;
  uint32[5] delta;
  uint[5] nEntries;
  uint[5] nEntries_prev;
  uint[5] prevTime;
  uint[5] prizePool;

  struct Entry{
    address fromAddress;
    uint timestamp;
    uint32[6] selection;
    bool shouldBubble;
    string ganbarou;
	}
  Entry[][5] entries;   //This is 5 dyn arrays, NOT a dyn array-of-arrays w/len=5!


  //contract events
  event NewEntryEvt(address indexed from, uint indexed timestamp, bool shouldBubble, uint32[6] selection);
  event PrintStrEvt(string out);
  event PrintIntEvt(uint out);

  //contract constructor
  function Lottery(uint16 _exponent) public{
    minter = msg.sender;

    exponent = _exponent;

    delta[0] = 60*60;
    delta[1] = delta[0]*24;
    delta[2] = delta[0]*7;
    delta[3] = delta[0]*30;
    delta[4] = delta[0]*365;

    nEntries[0] = 0;
    nEntries[1] = 0;
    nEntries[2] = 0;
    nEntries[3] = 0;
    nEntries[4] = 0;

    prizePool[0] = 0;
    prizePool[1] = 0;
    prizePool[2] = 0;
    prizePool[3] = 0;
    prizePool[4] = 0;

    nEntries_prev[0] = 0;
    nEntries_prev[1] = 0;
    nEntries_prev[2] = 0;
    nEntries_prev[3] = 0;
    nEntries_prev[4] = 0;

    prevTime[0] = block.timestamp;
    prevTime[1] = block.timestamp;
    prevTime[2] = block.timestamp;
    prevTime[3] = block.timestamp;
    prevTime[4] = block.timestamp;
  }

  //contract suicide  - to be removed...
  function kill() {
    if (msg.sender == minter){
      suicide(minter);
    }
  }

  //function that echos how much the entry to the draw is
  function hello(){
    PrintStrEvt("earthlottery.com");
    PrintIntEvt(10**exponent);
  }

  //contract entry point for players
  function play(uint32[6] selection, string ganbarou, uint16 drawID, bool shouldBubble){
    uint i=0;
    uint j=0;
    uint8 drawIndx=0;   //i.e. hourly draw...

    /*
    //sanity checks
    /*/
    //check entry amount isn't less than 10^exponent Weis!
    if(msg.value < 10**exponent){
      PrintStrEvt("ERROR: Minimum entry not sent. Please send the correct amount to enter.");
      msg.sender.send(msg.value);
      return;
    }

    //check message length OK
    if(bytes(ganbarou).length > 140){
      PrintStrEvt("ERROR: Invalid ganbarou. Max length is 140");
      msg.sender.send(msg.value);
      return;
    }

    //check valid draw ID chosen
    if(drawID==1 || drawID==24 || drawID==7 || drawID==12 || drawID==365){
      //OK
      drawIndx=hdwmy2indx(drawID);
    }else{
      PrintStrEvt("ERROR: Invalid drawID parameter. Please choose one of: {1,24,7,12,365}");
      msg.sender.send(msg.value);
      return;
    }

    //ensure the numbers chosen are unique and in range...
    for(i=0;i<selection.length;i++){
      if(selection[i]>getRange(nEntries_prev[drawIndx])){
        PrintStrEvt("ERROR: At least one of your chosen numbers is not in this draw. It is too big!");
        msg.sender.send(msg.value);
        return;
      }
      for(j=0;j<selection.length;j++){
        if(i!=j && selection[j]==selection[i] ){
          PrintStrEvt("ERROR: Your chosen numbers must be unique!");
          msg.sender.send(msg.value);
          return;
        }
      }
    }

    /*
    //sanity checks end
    */



    //entry amount:
    //the entry is rounded down to the nearest power of 10 exponent
    //anthing left over is returned to the sender
    uint val_return = msg.value - (10**exponent);
    //refund overpayment:
    if(val_return>0){
      msg.sender.send(val_return);
      PrintStrEvt("NOTICE: We refunded an overpayment");   //TODO: very careful!
    }

    nEntries[drawIndx]=nEntries[drawIndx]+1;
    prizePool[drawIndx]=prizePool[drawIndx]+(10**exponent);
    entries[nEntries[drawIndx]][drawIndx] =  Entry({fromAddress: msg.sender, timestamp: block.timestamp, shouldBubble: shouldBubble, selection: selection, ganbarou: ganbarou});

    PrintStrEvt("NOTICE: Entry recieved successfully. Good luck.");



    //Now, check if a draw should be run...
    if((block.timestamp - prevTime[drawIndx]) >= delta[drawIndx]){
      //run the draw!
      runDraw(drawIndx);
    }else{
      //do nothing...
      //wait for the next entry
    }
  }
  //manually run a draw (without entering...) - only minter address can initiate
  function manuallyRunDraw(uint8 drawIndx){   //TODO: check public OK - public by default?
    if(msg.sender!=minter){
      PrintStrEvt("ERROR: Only minter can do that");
      msg.sender.send(msg.value);
      return;
    }
    runDraw(drawIndx);
  }
  //if a valid timestamp is detected on a valid entry, the draw runs...
  function runDraw(uint8 drawIndx) private{   //TODO: check public/private
    uint256 pseudoRand = 0;
    uint i=0;
    uint nWinners=0;

    for(i=0;i<nEntries[drawIndx];i++){
      pseudoRand = pseudoRand + (uint256(block.blockhash(block.number)) ^ uint256(block.blockhash(block.number-1))) * uint256(entries[i][drawIndx].timestamp);
    }

    uint range=getRange(nEntries_prev[drawIndx]);
    uint[6] memory winningSelection;
    for(i=0;i<6;i++){
      winningSelection[i] = getNextUniqueRandomNumber(winningSelection,pseudoRand,range);
    }

    //and find winner(s):
    mapping (uint => Entry) winners;
    for(i=0;i<nEntries[0];i++){
      if(winningSelection[0] == entries[i][drawIndx].selection[0] &&
        winningSelection[1] == entries[i][drawIndx].selection[1] &&
        winningSelection[2] == entries[i][drawIndx].selection[2] &&
        winningSelection[3] == entries[i][drawIndx].selection[3] &&
        winningSelection[4] == entries[i][drawIndx].selection[4] &&
        winningSelection[5] == entries[i][drawIndx].selection[5]){

        winners[nWinners]=entries[i][drawIndx];
        nWinners=nWinners+1;
      }
    }

    if(nWinners==0){
      //pay minter commission
      minter.send(prizePool[drawIndx]/10);
      prizePool[drawIndx]=(prizePool[drawIndx]/10)*9;
    }else{
      //pay the winners!
      for(i=0;i<nWinners;i++){
        winners[i].fromAddress.send(prizePool[drawIndx]/nWinners);
      }
      //N.B. don't forget!
      prizePool[drawIndx]=0;
    }

    //N.B. clean up for next round
    nEntries_prev[drawIndx] = nEntries[drawIndx];
    nEntries[drawIndx]=0;
    prevTime[drawIndx]=block.timestamp;
    nWinners=0;  //to be sure, to be sure
  }
























  //Since this call changes nothing on the blockchain, it returns instantly and without any gas cost.
  function getRange(uint nEntries) constant public returns(uint){   //TODO: private?
    uint nBalls=6;
    while(nCr(nBalls,6)<nEntries){
      nBalls=nBalls+1;
    }
    return nBalls;
  }
  function hdwmy2indx(uint16 hdwmy) returns(uint8){
    if(hdwmy==1){
      return 0;
    }else if(hdwmy==24){
      return 1;
    }else if(hdwmy==7){
      return 2;
    }else if(hdwmy==12){
      return 3;
    }else if(hdwmy==365){
      return 4;
    }
    return 255;   //error code
  }
  function nCr(uint n, uint r) constant returns(uint){   //TODO: private?
    return factorial(n)/(factorial(r)*factorial(n-r));
  }
  function factorial(uint n) constant returns(uint){   //TODO: private
    if(n<=1){
      return 1;
    }else{
      return n * factorial(n-1);
    }
  }










  function getNextUniqueRandomNumber(uint[6] selection,uint pseudoRand,uint range) constant returns(uint){   //TODO: private
    uint validNumber=0;
    uint kk=0;

    for(kk=0;kk<selection.length;kk++){
      uint pertubation=0;
      while(!isUnique(selection,kk)){
        uint aNumber = getRandomNumber(range,pseudoRand,pertubation);
        if(aNumber>=1 && aNumber<=range){   //double-check: only assign if number is in range!!!
          selection[kk]=aNumber;
          validNumber=aNumber;
        }
        pertubation=pertubation+1;
      }
    }
    return validNumber;
  }
  function isUnique(uint[6] selection,uint upTo) constant returns(bool){   //TODO: private
    uint y=0;
    uint z=0;
    for(y=0;y<=upTo;y++){
      for(z=0;z<=upTo;z++){
        if(y==z){
          continue;
        }
        if(selection[y]==selection[z] || selection[y]==0){   //N.B. zero check!
          return false;
        }
      }
    }
    return true;
  }
  function getRandomNumber(uint range,uint256 pseudoRand,uint pertubation) constant returns(uint){   //TODO: private
    uint256 pseudoRand2 = pseudoRand ^ uint256(block.blockhash(block.number-(pertubation+1)));
    uint256 pertubation2 = pertubation % 7;   //6*35 = 215 and [0-6] in the range [0,255]

    pseudoRand2 = (pseudoRand2/(2^(35*pertubation2))) % range;

    return (pseudoRand2 + 1);   //N.B. - the +1 !!! (numbers start counting at 1, not 0)
  }
}
