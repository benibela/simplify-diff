{ Unified diff reader/writer

  Copyright (C) 2009 Benito van der Zander, benito@benibela.de, http://www.benibela.de

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or (at your option)
  any later version.

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.
}

unit diffreader;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils; 

type
EParseException=class(Exception);
TLineType=(ltBoth, ltOld, ltNew, ltMissingNewLine);
TChunk=record
  start1, len1, start2, len2: integer;
  lines: array of record
    s: string;
    typ: TLineType;
  end;
end;
TDiffFile = record
  oldFileDesc, newFileDesc: string;
  chunks: array of TChunk;
end;
TMultipleDiffFiles = array of record
  fileName:string;
  diff:TDiffFile;
end;
TGlobalDiffReadFlags=set of (gfVerboseOutputFileNames, gfVerboseOutputChunks);

//** These global flags affect how the files are read
//**(no other global variables are used/written to, so all procedures are re-entrant)
var globalDiffReadFlags: TGlobalDiffReadFlags;

procedure readChunk(var f: TextFile; out chunk:TChunk);
procedure readDiffFile(var f: TextFile; firstLine: string; out diffFile: TDiffFile; out nextLine: string);
procedure readDiffFile(var f: TextFile; out diffFile: TDiffFile);
procedure readMultipleDiffs(var f: TextFile; out multipleDiffs: TMultipleDiffFiles);

procedure writeChunk(var f: TextFile; const chunk:TChunk);
procedure writeDiffFile(var f: TextFile; const diffFile: TDiffFile);
procedure writeMultipleDiffs(var f: TextFile; const multipleDiffs: TMultipleDiffFiles);

//**simple modify function
procedure changeLineType(var chunk: TChunk; const lineID: longint; newType: TLineType);
procedure deleteLine(var chunk: TChunk; const lineID: longint);
procedure deleteChunk(var df: TDiffFile; const chunkID: longint);
procedure deleteDiffFile(var mdf: TMultipleDiffFiles; const diffFileID: longint);

//**diff utility functions
type TWhiteSpaceIgnore = set of (wsStart, wsEnd);
procedure stripIdenticalLines(var chunk: TChunk; whitespace: TWhiteSpaceIgnore);
procedure stripIdenticalLines(var df: TDiffFile; whitespace: TWhiteSpaceIgnore);
procedure stripIdenticalLines(var mdf: TMultipleDiffFiles; whitespace: TWhiteSpaceIgnore);

procedure stripFileEnding(var chunk: TChunk);
procedure stripFileEnding(var df: TDiffFile);
procedure stripFileEnding(var mdf: TMultipleDiffFiles);

function isChunkUnmodified(const chunk:TChunk):boolean;
procedure stripUnmodifiedChunks(var df: TDiffFile);
procedure stripUnmodifiedChunks(var mdf: TMultipleDiffFiles);

procedure stripUnmodifiedFiles(var mdf: TMultipleDiffFiles);

procedure removeAdditionalLines(var chunk: TChunk; intMaxCount: longint);
procedure removeAdditionalLines(var df: TDiffFile; intMaxCount: longint);
procedure removeAdditionalLines(var mdf: TMultipleDiffFiles; intMaxCount: longint);
implementation
const noNewLine:string='\ No newline at end of file';
procedure verboseOutput(s: string);
begin
  writeln(StdErr, s);
end;

procedure readChunk(var f: TextFile; firstLine:string; out chunk: TChunk);
  procedure readRange(var s: string; out start,len:longint);
  var ps, pc: longint;
  begin
    ps:=pos(' ',s);
    pc:=pos(',',s);
    if (ps < pc) or (pc<=0) then begin
      start:=StrToInt(copy(s,1,ps-1));
      len:=1;
    end else begin
      start:=StrToInt(copy(s,1,pc-1));
      len:=StrToInt(copy(s,pc+1,ps-pc-1));
    end;
    delete(s,1,ps);
  end;
var s:string;
    t1,t2: integer; //lines read so far
    nextStr: integer;
begin
  s:=firstLine;
  //chunk start: "@@ -s,l +s,l @@"
  if strlicomp(@s[1],'@@ -',4)<>0 then raise EParseException.Create('Expected @@ -, but got: '+s);
  delete(s,1,4);
  readRange(s,chunk.start1,chunk.len1);
  readRange(s,chunk.start2,chunk.len2);
  if gfVerboseOutputChunks in globalDiffReadFlags then
    verboseOutput('  Read chunk: -'+IntToStr(chunk.start1)+ ','+IntToStr(chunk.len1)+'  +'+IntToStr(chunk.start2)+','+IntToStr(chunk.len2));
  //writeln(StdErr,chunk.start1, ' ',chunk.len1, '  .  ',chunk.start2,chunk.len2);
  if s<>'@@' then raise EParseException.Create('Expected @@, but got: '+s);
  setlength(chunk.lines,chunk.len1+chunk.len2+2); //overestimated
  nextStr:=0;
  t1:=0;t2:=0;
  while (t1<chunk.len1) or (t2<chunk.len2) do begin
    readln(f,s);
    if s[1] in ['+','-',' '] then begin
      chunk.lines[nextStr].s:=copy(s,2,length(s)-1);
      case s[1] of
        ' ': begin
          chunk.lines[nextStr].typ:=ltBoth;
          t1+=1;
          t2+=1;
        end;
        '-': begin
          chunk.lines[nextStr].typ:=ltOld;
          t1+=1;
        end;
        '+': begin
          chunk.lines[nextStr].typ:=ltNew;
          t2+=1;
        end;
      end;
      nextStr+=1;
    end else if s =noNewLine then begin
      chunk.lines[nextStr].s:='wtf';
      chunk.lines[nextStr].typ:=ltMissingNewLine;
      nextStr+=1;
    end else raise EParseException.Create('Expected chunk line starting with - +, but got: '+s);
  end;
  SetLength(chunk.lines,nextStr); //truncate to real size
end;

procedure readChunk(var f: TextFile; out chunk: TChunk);
var s:string;
begin
  readln(f,s);
  readChunk(f,s,chunk);
end;

procedure readDiffFile(var f: TextFile; firstLine: string; out diffFile: TDiffFile; out nextLine: string);
var s:string;
begin
  s:=firstLine;
  if strlicomp(@s[1],'--- ',4) <> 0 then raise EParseException.Create('Expected --- , but got : '+s);
  diffFile.oldFileDesc:=copy(s,5,length(s));
  ReadLn(f, s);
  if strlicomp(@s[1],'+++ ',4) <> 0 then raise EParseException.Create('Expected +++ , but got : '+s);
  diffFile.newFileDesc:=copy(s,5,length(s));
  SetLength(diffFile.chunks,0);
  nextLine:='';
  while not eof(f) do begin
    ReadLn(f,s);
    if s='' then exit;
    if strlicomp(@s[1],'@@',2) =0 then begin
      setlength(diffFile.chunks,length(diffFile.chunks)+1);
      readChunk(f,s,diffFile.chunks[high(diffFile.chunks)]);
    end else if strlicomp(@s[1],'In',2)=0 then begin
      nextLine:=s;
      exit;
    end else raise EParseException.Create('Expected @@ for chunk or Index: for new file, but got: '+s);
  end;
end;

procedure readDiffFile(var f: TextFile; out diffFile: TDiffFile);
var s,temp:string;
begin
  ReadLn(f, s);
  readDiffFile(f,s,diffFile,temp);
end;

procedure readMultipleDiffs(var f: TextFile; out multipleDiffs: TMultipleDiffFiles);
var s, n:string;
  i: Integer;
begin
  ReadLn(f,s);
  if s='' then raise EParseException.Create('No input');
  if strlicomp(@s[1],'---',3) = 0 then begin
    SetLength(multipleDiffs,1);
    multipleDiffs[0].fileName:='';
    readDiffFile(f, s, multipleDiffs[0].diff,n );
    exit;
  end;
  SetLength(multipleDiffs,0);
  while (strlicomp(@s[1],'Index:',length('Index:')) = 0) do begin
    setlength(multipleDiffs,length(multipleDiffs)+1);
    multipleDiffs[high(multipleDiffs)].fileName:=copy(s,8,length(s));
    if gfVerboseOutputFileNames in globalDiffReadFlags then
      verboseOutput('Read diff for '+multipleDiffs[high(multipleDiffs)].fileName);
    readln(f,s);
    for i:=1 to length(s) do
      if s[i]<>'=' then EParseException.Create('Invalid input: Expected a line of =, but got "'+s+'"');
    readln(f,s);
    readDiffFile(f, s, multipleDiffs[high(multipleDiffs)].diff, n);
    s:=n;
    if s='' then
      if eof(f) then exit
      else readln(f,s);
  end;
end;

procedure writeChunk(var f: TextFile; const chunk: TChunk);
var
  i: Integer;
begin
  WriteLn(f,'@@ -',chunk.start1,',',chunk.len1, ' +', chunk.start2,',',chunk.len2,' @@');
  for i:=0 to high(chunk.lines) do
    case chunk.lines[i].typ of
      ltBoth: WriteLn(f,' ',chunk.lines[i].s);
      ltOld: WriteLn(f,'-',chunk.lines[i].s);
      ltNew: WriteLn(f,'+',chunk.lines[i].s);
      ltMissingNewLine: writeln(f,noNewLine);
    end;
end;

procedure writeDiffFile(var f: TextFile; const diffFile: TDiffFile);
var
  i: Integer;
begin
  WriteLn(f,'--- ',diffFile.oldFileDesc);
  WriteLn(f,'+++ ',diffFile.newFileDesc);
  for i:=0 to high(diffFile.chunks) do
    writeChunk(f,diffFile.chunks[i]);
end;

procedure writeMultipleDiffs(var f: TextFile;
  const multipleDiffs: TMultipleDiffFiles);
var
  i: Integer;
begin
  for i:=0 to high(multipleDiffs) do begin
    if (length(multipleDiffs)>1) or (multipleDiffs[i].fileName<>'') then begin
      WriteLn(f,'Index: ',multipleDiffs[i].fileName);
      WriteLn(f,'===================================================================');
    end;
    writeDiffFile(f,multipleDiffs[i].diff);
  end;
end;

procedure changeLineType(var chunk: TChunk; const lineID: longint;
  newType: TLineType);
begin
  if chunk.lines[lineID].typ in [ltBoth,ltOld] then chunk.len1-=1;
  if chunk.lines[lineID].typ in [ltBoth,ltNew] then chunk.len2-=1;
  chunk.lines[lineID].typ:=newType;
  if chunk.lines[lineID].typ in [ltBoth,ltOld] then chunk.len1+=1;
  if chunk.lines[lineID].typ in [ltBoth,ltNew] then chunk.len2+=1;
end;

procedure deleteLine(var chunk: TChunk; const lineID: longint);
var i:longint;
begin
  if chunk.lines[lineID].typ in [ltBoth,ltOld] then chunk.len1-=1;
  if chunk.lines[lineID].typ in [ltBoth,ltNew] then chunk.len2-=1;
  for i:=lineID+1 to high(chunk.lines) do
    chunk.lines[i-1]:=chunk.lines[i];
  setlength(chunk.lines,high(chunk.lines));
end;

procedure deleteChunk(var df: TDiffFile; const chunkID: longint);
var
  i: Integer;
begin
  for i := chunkID+1 to high(df.chunks) do
    df.chunks[i-1]:=df.chunks[i];
  setlength(df.chunks,high(df.chunks));
end;

procedure deleteDiffFile(var mdf: TMultipleDiffFiles; const diffFileID: longint);
var
  i: Integer;
begin
  for i := diffFileID+1 to high(mdf) do
    mdf[i-1]:=mdf[i];
  setlength(mdf,high(mdf));
end;

procedure stripIdenticalLines(var chunk: TChunk; whitespace: TWhiteSpaceIgnore);
  function equal(l1,l2:string):boolean;
  begin
    if wsStart in whitespace then begin
      l1:=TrimLeft(l1);
      l2:=TrimLeft(l2);
    end;
    if wsEnd in whitespace then begin
      l1:=TrimRight(l1);
      l2:=TrimRight(l2);
    end;
    result:=l1=l2;
  end;
var i,j,k:longint;
    temp:string;
begin
  i:=0;
  while i<=high(chunk.lines) do begin
    //search modified block
    if chunk.lines[i].typ in [ltBoth,ltNew,ltMissingNewLine] then begin
      i+=1; //either unmodified or only added (nothing is deleted)
    end else begin
      j:=i+1;
      while (chunk.lines[j].typ=ltOld) and (j<=high(chunk.lines)) do j+=1;
      if j>high(chunk.lines) then exit;
      //we found a modified block
      while (equal(chunk.lines[i].s,chunk.lines[j].s)) and (chunk.lines[i].typ=ltOld) do begin
        //mark as unmodified and remove added line
        changeLineType(chunk,i,ltBoth);
        if chunk.lines[j].typ=ltNew then begin
          i+=1;
          deleteLine(chunk,j);
          if j>high(chunk.lines) then exit;
        end else if chunk.lines[j].typ=ltBoth then begin
          //resort, equal line, removed ones, more...
          chunk.lines[i].typ:=ltBoth;
          chunk.lines[j].typ:=ltOld;
          i+=1;
          {temp:=chunk.lines[j].s;
          for k:=j downto i+2 do
            chunk.lines[k]:=chunk.lines[k-1];
          i+=1;
          chunk.lines[i].s:=temp;
          chunk.lines[i].typ:=ltOld;
          j+=1;}
          while (chunk.lines[j].typ=ltOld) and (j<=high(chunk.lines)) do j+=1;
        end;
      end;
      if (not equal(chunk.lines[i].s,chunk.lines[j].s)) and (j+1<=high(chunk.lines))
         and (equal(chunk.lines[i+1].s,chunk.lines[j+1].s)) and (chunk.lines[i+1].typ=ltOld)
         and (chunk.lines[j+1].typ=ltNew) and
         (chunk.lines[i].typ=ltOld) and (chunk.lines[j].typ=ltNew) //safety check, should always be true
         then begin
        //look ahead, only  one line is modified
        //TODO: longer look ahead
        //TODO. [A][I1][U1][N][I2][U2] => [A][N][I1][U1][U2] (resorting with larger lookahead, problem: find matching line)
        temp:=chunk.lines[j].s;
        for k:=j downto i+2 do chunk.lines[k]:=chunk.lines[k-1];
        chunk.lines[i+1].s:=temp;
        chunk.lines[i+1].typ:=ltNew;
        i+=2;
      end else i:=j;
    end;

  end;
end;

procedure stripIdenticalLines(var df: TDiffFile; whitespace: TWhiteSpaceIgnore);
var
  i: Integer;
begin
  for i:=0 to high(df.chunks) do
    stripIdenticalLines(df.chunks[i],whitespace);
end;

procedure stripIdenticalLines(var mdf: TMultipleDiffFiles; whitespace: TWhiteSpaceIgnore);
var
  i: Integer;
begin
  for i:=0 to high(mdf) do
    stripIdenticalLines(mdf[i].diff,whitespace);
end;

procedure stripFileEnding(var chunk: TChunk);
var
  i: Integer;
begin
  for i:=high(chunk.lines) downto 0 do
    if chunk.lines[i].typ = ltMissingNewLine then deleteLine(chunk,i);
end;

procedure stripFileEnding(var df: TDiffFile);
var
  i: Integer;
begin
  for i:=0 to high(df.chunks) do
    stripFileEnding(df.chunks[i]);
end;

procedure stripFileEnding(var mdf: TMultipleDiffFiles);
var
  i: Integer;
begin
  for i:=0 to high(mdf) do
    stripFileEnding(mdf[i].diff);
end;

function isChunkUnmodified(const chunk: TChunk): boolean;
var i:longint;
begin
  for i:=0 to high(chunk.lines) do
    if not (chunk.lines[i].typ in [ltBoth,ltMissingNewLine]) then
      exit(false);
  result:=true;
end;

procedure stripUnmodifiedChunks(var df: TDiffFile);
var
  i: Integer;
begin
  for i:=high(df.chunks) downto 0 do
    if isChunkUnmodified(df.chunks[i]) then deleteChunk(df,i);
end;

procedure stripUnmodifiedChunks(var mdf: TMultipleDiffFiles);
var
  i: Integer;
begin
  for i:=0 to high(mdf) do
    stripUnmodifiedChunks(mdf[i].diff);
end;

procedure stripUnmodifiedFiles(var mdf: TMultipleDiffFiles);
var i:longint;
begin
  for i:=high(mdf) downto 0 do
    if length(mdf[i].diff.chunks)=0 then
      deleteDiffFile(mdf,i);
end;

procedure removeAdditionalLines(var chunk: TChunk; intMaxCount: longint);
var p:longint;
  i: Integer;
begin
  //from the end
  p:=high(chunk.lines);
  while (p>=0) and (chunk.lines[p].typ=ltBoth) do p-=1;
  if high(chunk.lines)-p>intMaxCount then begin//too much lines
    p:=p+1+intMaxCount; //new length
    chunk.len1-=length(chunk.lines)-p;
    chunk.len2-=length(chunk.lines)-p;
    SetLength(chunk.lines,p);
  end;
  //from the beginning
  p:=0;
  while (p<=high(chunk.lines)) and (chunk.lines[p].typ=ltBoth) do p+=1;
  if p>intMaxCount then begin
    p:=p-intMaxCount; //so many to delete
    for i:=0 to high(chunk.lines)-p do
      chunk.lines[i]:=chunk.lines[i+p];
    setlength(chunk.lines,length(chunk.lines)-p);
    chunk.start1+=p;
    chunk.start2+=p;
    chunk.len1-=p;
    chunk.len2-=p;
  end;
end;

procedure removeAdditionalLines(var df: TDiffFile; intMaxCount: longint);
var
  i: Integer;
begin
  for i:=0 to high(df.chunks) do
    removeAdditionalLines(df.chunks[i],intMaxCount);
end;

procedure removeAdditionalLines(var mdf: TMultipleDiffFiles;
  intMaxCount: longint);
var
  i: Integer;
begin
  for i:=0 to high(mdf) do
    removeAdditionalLines(mdf[i].diff,intMaxCount);
end;

end.

