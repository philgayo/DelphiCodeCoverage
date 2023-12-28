(***********************************************************************)
(* Delphi Code Coverage                                                *)
(*                                                                     *)
(* A quick hack of a Code Coverage Tool for Delphi                     *)
(* by Christer Fahlgren and Nick Ring                                  *)
(*                                                                     *)
(* This Source Code Form is subject to the terms of the Mozilla Public *)
(* License, v. 2.0. If a copy of the MPL was not distributed with this *)
(* file, You can obtain one at http://mozilla.org/MPL/2.0/.            *)

unit JacocoCoverageFileUnit;

interface

uses
  I_Report,
  I_CoverageStats,
  JclSimpleXml,
  I_CoverageConfiguration,
  ClassInfoUnit,
  I_LogManager;

type
  TJacocoCoverageReport = class(TInterfacedObject, IReport)
  strict private
    FCoverageConfiguration: ICoverageConfiguration;

    procedure AddModuleInfo(
      AAllElement: TJclSimpleXMLElem;
      const AModuleInfo: TModuleInfo);
    procedure AddClassInfo(
      ASourceFileElement: TJclSimpleXMLElem;
      const AClassInfo: TClassInfo);
    procedure AddClassStats(
      const ARootElement: TJclSimpleXMLElem;
      const AClass: TClassInfo);
    procedure AddMethodInfo(
      AClassElement: TJclSimpleXMLElem;
      const AMethod: TProcedureInfo);
    procedure AddMethodStats(
      const ARootElement: TJclSimpleXMLElem;
      const AMethod: TProcedureInfo);
    procedure AddSourceStats(
      const ARootElement: TJclSimpleXMLElem;
      const AModule: TModuleInfo);

    procedure AddCoverageElement(const RootElement: TJclSimpleXMLElem;
      const AType: string; const TotalCoveredCount, TotalUncoveredCount: Integer);
  public
    constructor Create(const ACoverageConfiguration: ICoverageConfiguration);

    procedure Generate(
      const ACoverage: ICoverageStats;
      const AModuleInfoList: TModuleList;
      const ALogManager: ILogManager);
  end;

  TJacocoCoverageReportMerger = class helper for TJacocoCoverageReport
    class function MergeCoverageStatsForGenerics(const ACoverageStatsIn: ICoverageStats): ICoverageStats;
  end;

implementation

uses
  System.DateUtils,
  System.StrUtils,
  System.SysUtils,
  System.Math,
  JclFileUtils,
  CoverageStats;

constructor TJacocoCoverageReport.Create(
  const ACoverageConfiguration: ICoverageConfiguration);
begin
  inherited Create;
  FCoverageConfiguration := ACoverageConfiguration;
end;

procedure TJacocoCoverageReport.Generate(
  const ACoverage: ICoverageStats;
  const AModuleInfoList: TModuleList;
  const ALogManager: ILogManager);

var
  StatsElement: TJclSimpleXMLElem;

  procedure AddValueElement(const AElementName: string; const AValue: Integer);
  begin
    StatsElement.Items
      .Add(AElementName)
      .Properties.Add('value', AValue);
  end;

  procedure AddElement(AElement: TJclSimpleXMLElem; const APropertyName: string; const AValue: Integer); overload;
  begin
    AElement.Properties.Add(APropertyName, AValue);
  end;

  procedure AddElement(AElement: TJclSimpleXMLElem; const APropertyName: string; const AValue: String); overload;
  begin
    AElement.Properties.Add(APropertyName, AValue);
  end;

var
  Uid: TGuid;
  Result: HResult;

  ModuleInfo: TModuleInfo;
  XML: TJclSimpleXML;
  SessionElement: TJclSimpleXMLElem;
begin
  ALogManager.Log('Generating jacoco xml report');

  XML := TJclSimpleXML.Create;
  try
    // Prolog doesn't seem to get written properly (with carriage returns)
    XML.Prolog.AddDocType('report PUBLIC "-//JACOCO//DTD Report 1.0//EN" "report.dtd"');
    XML.Prolog.Standalone := true;


    XML.Root.Name := 'report';
    AddElement(XML.Root, 'name', 'debug');   // For now

    SessionElement := XML.Root.Items.Add('session');

    Result := CreateGuid(Uid);
    if Result = S_OK then
      SessionElement.Properties.Add('id', GuidToString(Uid));    { TODO: Not sure of the format }
    SessionElement.Properties.Add('start', DateTimeToUnix(now)); { TODO: Should be a start time }
    SessionElement.Properties.Add('dump', DateTimeToUnix(now));

    for ModuleInfo in AModuleInfoList do
    begin
      AddModuleInfo(XML.Root, ModuleInfo);
    end;

    XML.SaveToFile(
      PathAppend(FCoverageConfiguration.OutputDir, 'jacoco.xml')
    );
  finally
    XML.Free;
  end;
end;


procedure TJacocoCoverageReport.AddModuleInfo(
  AAllElement: TJclSimpleXMLElem;
  const AModuleInfo: TModuleInfo);
var
  PackageElement: TJclSimpleXMLElem;
  SourceFileElement: TJclSimpleXMLElem;
  ClassInfo: TClassInfo;
begin
  PackageElement := AAllElement.Items.Add('package');
  PackageElement.Properties.Add('name', AModuleInfo.ModuleName.Replace('.','/'));

  for ClassInfo in AModuleInfo do
  begin
    AddClassInfo(PackageElement, ClassInfo);
  end;

  SourceFileElement := PackageElement.Items.Add('sourcefile');
  SourceFileElement.Properties.Add('name', AModuleInfo.ModuleFileName);

  { TODO: Lines }
  AddSourceStats(SourceFileElement, AModuleInfo);
end;

procedure TJacocoCoverageReport.AddSourceStats(
  const ARootElement: TJclSimpleXMLElem; const AModule: TModuleInfo);
begin
  AddCoverageElement(ARootElement,
          'LINE',
          AModule.CoveredLineCount,
          AModule.LineCount - AModule.CoveredLineCount);

  AddCoverageElement(ARootElement,
          'METHOD',
          AModule.CoveredMethodCount,
          AModule.MethodCount - AModule.CoveredMethodCount);

  AddCoverageElement(ARootElement,
          'CLASS',
          AModule.CoveredClassCount,
          AModule.ClassCount - AModule.CoveredClassCount);
end;

procedure TJacocoCoverageReport.AddClassInfo(
  ASourceFileElement: TJclSimpleXMLElem;
  const AClassInfo: TClassInfo);
var
  Method: TProcedureInfo;
  ClassElement: TJclSimpleXMLElem;
begin
  ClassElement := ASourceFileElement.Items.Add('class');
  { TODO: Check whether this is enough }
  ClassElement.Properties.Add('name', AClassInfo.Module.Replace('.','/') + '/' + AClassInfo.TheClassName);

  for Method in AClassInfo do
    AddMethodInfo(ClassElement, Method);

  AddClassStats(ClassElement, AClassInfo);
end;

procedure TJacocoCoverageReport.AddClassStats(
  const ARootElement: TJclSimpleXMLElem;
  const AClass: TClassInfo);
begin
  AddCoverageElement(ARootElement,
          'LINE',
          AClass.CoveredLineCount,
          AClass.LineCount - AClass.CoveredLineCount);

  AddCoverageElement(ARootElement,
          'METHOD',
          AClass.CoveredProcedureCount,
          AClass.ProcedureCount - AClass.CoveredProcedureCount);

//  AddCoverageElement(ARootElement,
//          'CLASS',
//          AClass.,
//          100 - AClass.PercentCovered);
end;

procedure TJacocoCoverageReport.AddMethodInfo(
  AClassElement: TJclSimpleXMLElem;
  const AMethod: TProcedureInfo);
var
  MethodElement: TJclSimpleXMLElem;
begin
  MethodElement := AClassElement.Items.Add('method');
  MethodElement.Properties.Add('name', AMethod.Name);
  MethodElement.Properties.Add('desc', '()'); {TODO: Not sure we can pull this out }
  AddMethodStats(MethodElement, AMethod);
end;

procedure TJacocoCoverageReport.AddMethodStats(
  const ARootElement: TJclSimpleXMLElem;
  const AMethod: TProcedureInfo);
//var
//  IsCovered: Integer;
begin
//  IsCovered := IfThen(AMethod.PercentCovered > 0, 1, 0);

  { TODO: Not sure about these either! }

  // INSTRUCTION
  { TODO: Is this the same as LINE? }
//  AddCoverageElement(ARootElement,
//          'counter',
//          'INSTRUCTION',
//          AMethod.CoveredLineCount,
//          AMethod.LineCount - AMethod.CoveredLineCount);

  // LINE
  AddCoverageElement(ARootElement,
          'LINE',
          AMethod.CoveredLineCount,
          AMethod.LineCount - AMethod.CoveredLineCount);

//  AddCoverageElement(ARootElement,
//          'METHOD',
//          AMethod.PercentCovered,
//          100 - AMethod.PercentCovered);

//  AddCoverageElement(ARootElement,
//          'counter',
//          'INSTRUCTION',
//          AMethod.CoveredLineCount,
//          AMethod.LineCount - AMethod.CoveredLineCount);

//   AddCoverageElement(ARootElement,
//          'counter',
//          'COMPLEXITY',
//          AMethod.CoveredLineCount,
//          AMethod.LineCount - AMethod.CoveredLineCount);


  (*
  AddCoverageElement(
    ARootElement, 'counter',
    AMethod.CoveredLineCount, AMethod.LineCount
  );

  AddCoverageElement(
    ARootElement, 'counter',
    AMethod.CoveredLineCount, AMethod.LineCount
  );

  AddCoverageElement(
    ARootElement, 'counter',
    AMethod.CoveredLineCount, AMethod.LineCount
  );
  *)
end;

procedure TJacocoCoverageReport.AddCoverageElement(
  const RootElement: TJclSimpleXMLElem;
  const AType: string;
  const TotalCoveredCount, TotalUncoveredCount: Integer);
var
  CoverageElement: TJclSimpleXMLElem;
begin
  CoverageElement := RootElement.Items.Add('counter');
  CoverageElement.Properties.Add('type', AType);
  CoverageElement.Properties.Add('covered', TotalCoveredCount);
  CoverageElement.Properties.Add('missed', TotalUncoveredCount);

end;


{$REGION 'TJacocoCoverageReportMerger'}

class function TJacocoCoverageReportMerger.MergeCoverageStatsForGenerics(
  const ACoverageStatsIn: ICoverageStats): ICoverageStats;
var
  i, j, line: Integer;
  LModuleStats, LUnitStats, LResultStats: ICoverageStats;
  FResultModuleName, FResultUnitName: String;
  LCoverageLine: TCoverageLine;
begin
  Result := TCoverageStats.Create(ACoverageStatsIn.Name, ACoverageStatsIn.Parent);

  //Loop all modules
  for i := 0 to ACoverageStatsIn.Count - 1 do begin
    LModuleStats := ACoverageStatsIn.CoverageReport[i];

    //Loop all units
    for j := 0 to LModuleStats.Count - 1 do begin
      LUnitStats := LModuleStats.CoverageReport[j];

      FResultModuleName := LUnitStats.Name.Substring(0, LUnitStats.Name.LastIndexOf('.'));
      FResultUnitName := LUnitStats.Name;

      LResultStats := Result.CoverageReportByName[FResultModuleName].CoverageReportByName[FResultUnitName];

      //Add all coverage lines
      for line := 0 to ACoverageStatsIn.CoverageReport[i].CoverageReport[j].GetCoverageLineCount - 1 do begin
        LCoverageLine := ACoverageStatsIn.CoverageReport[i].CoverageReport[j].CoverageLine[line];
        LResultStats.AddLineCoverage(LCoverageLine.LineNumber, LCoverageLine.LineCount);
      end;
    end;
  end;

  Result.Calculate;
end;

{$REGION}

end.
