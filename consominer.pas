program consominer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
   cthreads,
  {$ENDIF}
  Classes, sysutils, nosocoreunit {$IFDEF UNIX}, UTF8Process{$ENDIF}
  { you can add units after this };

Type
  TMinerThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

  TMainThread = class(TThread)
    protected
      procedure Execute; override;
    public
      Constructor Create(CreateSuspended : boolean);
    end;

var
  ArrMiners : Array of TMinerThread;
  MainThread : TMainThread;
  CPUspeed: extended;
  HashesToTest : integer = 5000;
  FirstRun : boolean = true;

constructor TMinerThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := True;
End;

constructor TMainThread.Create(CreateSuspended : boolean);
Begin
inherited Create(CreateSuspended);
FreeOnTerminate := True;
End;

procedure TMinerThread.Execute;
var
  BaseHash, ThisHash, ThisDiff : string;
  ThisSolution : TSolution;
  MyID : integer;
  ThisPrefix : string = '';
  Counter : int64 = 100000000;
  EndThisThread : boolean = false;
  TempHashes : integer = 0;
  LastRefresh : int64 = 0;
Begin
MyID := ThreadPrefix-1;
ThisPrefix := GetPrefix(MinerID)+GetPrefix(MyID)+'!!!!!';
While ((not FinishMiners) and (not EndThisThread)) do
   begin
   //BaseHash := GetHashToMine;
   BaseHash := ThisPrefix+Counter.ToString;
   inc(Counter);inc(TempHashes);
   ThisHash := NosoHash(BaseHash+Address);
   ThisDiff := CheckHashDiff(TargetHash,ThisHash);
   if ThisDiff<TargetDiff then
      begin
      ThisSolution.Target:=TargetHash;
      ThisSolution.Hash  :=BaseHash;
      ThisSolution.Diff  :=ThisDiff;
      AddSolution(ThisSolution);
      end;
   if LastRefresh+4<UTCTime then
      begin
      AddIntervalHashes(TempHashes);
      TempHashes := 0;
      end;
   if ((Counter = 100000000+HashesToTest) and (Testing)) then EndThisThread := true;
   end;
dec(OpenThreads);
End;

procedure TMainThread.Execute;
Begin
While not FinishProgram do
   begin
   CheckLogs;
   if runminer then
      begin
      While Length(RejectedSols)>0 do
         begin
         write(Length(RejectedSols));
         AddSolution(RejectedSols[0]);
         Delete(RejectedSols,0,1);
         end;
      While SolutionsLength>0 do
         begin
         PushSolution(GetSolution);
         end;
      if ( (BlockAge>585) and (TargetDiff<MaxDiff) ) then
         Begin
         FinishMiners := true;
         PauseMiners := true;
         GetTotalHashes;
         end;
      if ( (BlockAge >= 610) and (LastSync+10<UTCTime) ) then
         begin
         LastSync := UTCTime;
         CheckSource;
         if NewBlock then
            begin
            NewBlock := False;
            GoodThis := 0;
            SentThis := 0;
            Miner_Counter := 100000000;
            LastSpeedCounter := 100000000;
            FinishMiners := false;
            PauseMiners := false;
            for counter2 := 1 to CPUCount do
                begin
                ThreadPrefix := counter2;
                ArrMiners[counter2-1] := TMinerThread.Create(true);
                ArrMiners[counter2-1].FreeOnTerminate:=true;
                ArrMiners[counter2-1].Start;
                Sleep(1);
                end;
            OpenThreads := CPUCount;
            writeln(#13,'-----------------------------------------------------------------------------');
            Writeln(Format('Block: %d / Address: %s / Cores: %d',[Consensus.block,address,cpucount]));
            Writeln(Format('%s / Target: %s / %s / [%d]' ,[UpTime,Copy(TargetHash,1,10),SourceStr,TotalMinedBlocks]));
            end;
         end;
      if ( (LastSpeedUpdate+4 < UTCTime) and (not Testing) ) then
         begin
         MiningSpeed := GetTotalHashes / (UTCTime-LastSpeedUpdate);
         if MiningSpeed <0 then MiningSpeed := 0;
         if SyncErrorStr <> '' then write(#13,Format('%s',[SyncErrorStr]))
         else
            begin
            if OpenThreads>0 then write(#13,Format('[%d] Age: %4d / Best: %10s / Speed: %8.2f H/s / {%d}',[OpenThreads,BlockAge,Copy(TargetDiff,1,10),MiningSpeed,GoodThis]))
            else write(#13,Format('%0:-79s',['Waiting next block']));
            end;
         LastSpeedUpdate := UTCTime;
         end;
      end;
   sleep(1000);
   end;
End;

{$R *.res}

BEGIN // Program Start
InitCriticalSection(CS_Counter);
InitCriticalSection(CS_MinerData);
InitCriticalSection(CS_Solutions);
InitCriticalSection(CS_Log);
InitCriticalSection(CS_Interval);
Assignfile(datafile, 'consominer.cfg');
Assignfile(logfile, 'log.txt');
Assignfile(OldLogFile, 'oldlogs.txt');
Consensus := Default(TNodeData);
If not ResetLogs then
   begin
   writeln('Error reseting log files');
   Exit;
   end;
SetLEngth(ARRAY_Nodes,0);
SetLEngth(Solutions,0);
SetLEngth(RejectedSols,0);
SetLEngth(LogLines,0);
MaxCPU:= {$IFDEF UNIX}GetSystemThreadCount{$ELSE}GetCPUCount{$ENDIF};
SetLength(ArrMiners,MaxCPU);  // Avoid overclocking
if not FileExists('consominer.cfg') then savedata();
loaddata();
LoadSeedNodes;
writeln('Consominer Nosohash '+AppVersion);
writeln('Built using FPC '+fpcVersion);
Writeln(GetOs+' --- '+MaxCPU.ToString+' CPUs --- '+Length(array_nodes).ToString+' Nodes');
writeln('Using '+address+' with '+CPUCount.ToString+' cores');
if not autostart then writeln('Please type help to get a list of commands');
MainThread := TMainThread.Create(true);
MainThread.FreeOnTerminate:=true;
MainThread.Start;
REPEAT
   command := '';
   if FirstRun then
      begin
      FirstRun := false;
      if AutoStart then //Command := 'MINE';
         begin
         if IsValidHashAddress(Address) then Command := 'MINE'
         else WriteLn('Invalid miner address');
         end;
      end;
   if command = '' then
      begin
      write('> ');
      readln(command);
      end;
   if Uppercase(Parameter(command,0)) = 'ADDRESS' then
      begin
      if IsValidHashAddress(Parameter(command,1)) then
         begin
         address := parameter(command,1);
         savedata();
         writeln ('Mining address set to : '+address);
         end
      else WriteLn('Invalid miner address');
      end
   else if Uppercase(Parameter(command,0)) = 'CPU' then
      begin
      cpucount := StrToIntDef(parameter(command,1),CPUCount);
      savedata();
      writeln ('Mining CPUs set to : '+CPUCount.ToString);
      end
   else if Uppercase(Parameter(command,0)) = 'TEST' then
      begin
      Testing:= true;
      for counter :=1 to MaxCPU do
         begin
         write('Testing with '+counter.ToString+' CPUs: ');
         TestStart := GetTickCount64;
         FinishMiners := false;
         Miner_Counter := 1000000000-(HashesToTest*counter);
         ActiveMiners := counter;
         for counter2 := 1 to counter do
            begin
            ThreadPrefix := counter2;
            ArrMiners[counter2-1] := TMinerThread.Create(true);
            ArrMiners[counter2-1].FreeOnTerminate:=true;
            ArrMiners[counter2-1].Start;
            sleep(1);
            end;
         OpenThreads := counter;
         REPEAT
            sleep(1)
         until OpenThreads = 0;
         TestEnd := GetTickCount64;
         TestTime := (TestEnd-TestStart);
         CPUSpeed := HashesToTest/(testtime/1000);
         writeln(FormatFloat('0.00',CPUSpeed)+' -> '+FormatFloat('0.00',CPUSpeed*counter)+' h/s');
         end;
      Testing := false;
      end
   else if Uppercase(Parameter(command,0)) = 'EXIT' then
      begin
      DoNothing;
      end
   else if Uppercase(Parameter(command,0)) = 'AUTOSTART' then
      begin
      autostart := StrToBoolDef(parameter(command,1),autostart);
      savedata();
      writeln ('Autostart set to : '+BoolToStr(autostart,true));
      end
   else if Uppercase(Parameter(command,0)) = 'MINERID' then
      begin
      if  StrToIntDef(parameter(command,1),-1)<0 then
         WriteLn('MinerID must be a number between 0-8100')
      else
         begin
         MinerID := StrToIntDef(parameter(command,1),MinerID);
         savedata();
         writeln ('MinerID set to : '+MinerID.ToString);
         end;
      end
   else if Uppercase(Parameter(command,0)) = 'MINE' then
      begin
      if not isvalidHashAddress(Address) then
         begin
         WriteLn('Invalid miner address');
         continue;
         end;
      Repeat
         Write('Syncing...',#13);
         sleep(100);
      until CheckSource;
      Writeln(format('Block: %d / Age: %d secs / Hash: %s',[Consensus.block,UTCTime-Consensus.LBTimeEnd,Consensus.LBHash]));
      LastSync := UTCTime;
      RunMiner := true;
      NewBlock := false;
      If SoloMining then Miner_Prefix := GetPrefix(MinerID);
      writeln('Mining with '+CPUcount.ToString+' CPUs and Prefix '+Miner_Prefix);
      if SoloMining then SourceStr := 'Mainnet' else SourceStr := '?????';
      writeln('Press CTRL+C to finish');
      ToLog('********************************************************************************');
      ToLog('Mining session opened');
      GetTotalHashes;
      FinishMiners := false;
      Miner_Counter := 100000000;
      LastSpeedCounter := 100000000;
      StartMiningTimeStamp := UTCTime;
      SentThis := 0;
      GoodThis := 0;
      writeln('-----------------------------------------------------------------------------');
      Writeln(Format('Block: %d / Address: %s / Cores: %d',[Consensus.block, address,cpucount]));
      Writeln(Format('%s / Target: %s / %s / [%d]' ,[UpTime,Copy(TargetHash,1,10),SourceStr,TotalMinedBlocks]));
      for counter2 := 1 to CPUCount do
         begin
         ThreadPrefix := counter2;
         ArrMiners[counter2-1] := TMinerThread.Create(true);
         ArrMiners[counter2-1].FreeOnTerminate:=true;
         ArrMiners[counter2-1].Start;
         sleep(1);
         end;
      OpenThreads := CPUCount;
      Repeat
         Sleep(10);
      until FinishProgram;
      end
   else if Uppercase(Parameter(command,0)) = 'HELP' then ShowHelp
   else if Uppercase(Parameter(command,0)) = 'SETTINGS' then ShowSettings
   else if Uppercase(Parameter(command,0)) = 'SOURCE' then WriteLn('Not implemented')
   //else if Uppercase(Parameter(command,0)) = 'COUNT' then Writeln('Active threads : '+OpenThreads.ToString) // debugonly
   else if Command <> '' then writeln('Invalid command');
UNTIL Uppercase(Command) = 'EXIT';
DoneCriticalSection(CS_Counter);
DoneCriticalSection(CS_MinerData);
DoneCriticalSection(CS_Solutions);
DoneCriticalSection(CS_Log);
DoneCriticalSection(CS_Interval);
END.// END PROGRAM

