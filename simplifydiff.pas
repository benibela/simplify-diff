program simplifydiff;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  diffreader,rcmdline //you can download these two files from www.benibela.de/components_en.html
  { you can add units after this }
;

var diffs: TMultipleDiffFiles;
    cmd: TCommandLineReader;
    ws:TWhiteSpaceIgnore;
begin
  cmd:=TCommandLineReader.create;
  cmd.declareFlag('strip-identical-lines','If unmodified lines are stored as modified, they are converted to unmodified ones', true);
  cmd.declareFlag('strip-unmodified-chunks','Removes chunks which aren''t modified', true);
  cmd.declareFlag('strip-unmodified-files','Remove files which aren''t modified (implies strip-unmodified-chunks)', true);
  cmd.declareFlag('strip-file-ending','Don''t care if the file ends with a new line', true);
  //cmd.declareFlag('remove-white-space-lines','Removes every modified line if it contains white space', false);
  cmd.declareFlag('ignore-starting-whitespace','Ignore change of white space at line start', true);
  cmd.declareFlag('ignore-ending-whitespace','Ignore change of white space at line end', true);
  cmd.declareInt('max-unchanged-lines','Removes unmodified lines at the start/end of a chunk if there are more (use -1 for infinity)',3);

  cmd.declareFlag('verbose-read-files','Prints a list of all files contained in the diff while reading',true);
  cmd.declareFlag('verbose-read-chunks','Prints a list of all chunks contained in the diff');

  globalDiffReadFlags:=[];
  if cmd.readFlag('verbose-read-files') then include(globalDiffReadFlags,gfVerboseOutputFileNames);
  if cmd.readFlag('verbose-read-chunks') then include(globalDiffReadFlags,gfVerboseOutputChunks);
  readMultipleDiffs(Input,diffs);

  if cmd.readFlag('strip-file-ending') then
    stripFileEnding(diffs);
  if cmd.readFlag('strip-identical-lines') then begin
    ws:=[];
    if cmd.readFlag('ignore-starting-whitespace') then include(ws,wsStart);
    if cmd.readFlag('ignore-ending-whitespace') then include(ws,wsEnd);
    stripIdenticalLines(diffs,ws);
  end;
  if cmd.readFlag('strip-unmodified-chunks') or cmd.readFlag('strip-unmodified-files') then
    stripUnmodifiedChunks(diffs);
  if cmd.readInt('max-unchanged-lines') <>-1 then
    removeAdditionalLines(diffs, cmd.readInt('max-unchanged-lines'));
  if cmd.readFlag('strip-unmodified-files') then
    stripUnmodifiedFiles(diffs);

  writeMultipleDiffs(Output,diffs);
end.

