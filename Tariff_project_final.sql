-- =============================================
-- Author:      Evelyn Byer
-- Create date: February 22, 2019
-- Description: 
-- Creating two procedures each for calculating 2017-18 and 2018-19 NHS tariffs
--		1) proc usp_tariff19_test100999/usp_tariff17_test100999 takes individual inputs and creates a table of tariffs
--		2) proc usp_nhs_tariff19_table/usp_nhs_tariff17_table takes a table name in quotes as input and outputs a table with the original input values + calculated tariffs
-- Join resulting created tables stage.calc_tariff_19/stage.calc_tariff_17 with hes_data table, creating two new tables including all hes_data + calculated tariffs
--	(final.tariffs19/final.tariffs17)
--
-- ****Note: in order to run this script at least three tables are necessary: NHS HRG APC Tariffs for 2017-18 (stage.tariff1718), NHS HRG APC Tariffs for 2018-19 (stage.tariff1819), and HES_multiepisode with joined HRG codes ([dbo].[HRG_and_HSe2]).
-- ****Here, dummy data for the HES data (including the grouped HRG codes) is used, while real NHS tariff data is used.
-- ****Uncomment testing sections to test between creating procedures, otherwise, can be run all the way through.
-- =============================================

------------------------------------------------------------------------------------------------------------
--creating proc that takes in five seperate inputs and inserts one row into table with tariff (2017-18)
create proc usp_tariff19_test100999
--alter proc usp_tariff19_test100999
@HRG_code varchar(5), @epi_type varchar(50), @stay_days int, @hesid varchar(20), @diag_01 varchar(20)
as

if
	@epi_type not in ('Ordinary elective','11','12','13','Non-elective','21', '25','28','2A','2B','99')
	begin
		print 'Wrong episode type input. Must input HRG code, episode type, and # of days of spell. Episode type must be one of the following: Ordinary elective, Non-elective or the ADMIMETH code from HES data'
		return
	end
Declare @tariff int
Select
@tariff = case
	when @stay_days <2 AND Reduced_emergency_tariff is not null and @epi_type like 'Non-elective' then Reduced_emergency_tariff 	
	when @stay_days <= Trim_point_days then base_price
	when @stay_days > Trim_point_days then (base_price + (@stay_days - Trim_point_days) * Long_stay_payment_per_day)
	end
from
(
Select
	case
		when @epi_type in ('Ordinary elective','11','12','13') and @stay_days = 0 then coalesce(cast([Combined day case / ordinary elective spell tariff (£)] as money),cast([Day case spell tariff (£)] as money))
		when @epi_type in ('Ordinary elective','11','12','13') and @stay_days != 0 then coalesce(cast([Combined day case / ordinary elective spell tariff (£)] as money),cast([Ordinary elective spell tariff (£)] as money))
		when @epi_type in ('Non-elective', '21', '25','28','2A','2B','99') then [Non-elective spell tariff (£)]
	end base_price
	,case
		when @epi_type in ('Ordinary elective','11','12','13') then [Ordinary elective long stay trim point (days)]
		when @epi_type in ('Non-elective', '21', '25','28','2A','2B','99') then [Non-elective long stay trim point (days)]
	end Trim_point_days
	,[Per day long stay payment (for days exceeding trim point) (£)] Long_stay_payment_per_day
	,[Reduced short stay emergency tariff (£)] Reduced_emergency_tariff
from
(	
Select
*
from stage.tariff1819
where [hrg code] like @hrg_code
) t
)p


if @tariff is null
begin
print('Tariff calculation NULL, HRG code likely not valid')
return
end

if object_id('stage.calc_tariff_19') is null
	begin 
		create table stage.calc_tariff_19 (HRG_code varchar(5), Epitype varchar(50), stay_days int, tariff_calc int, hesid varchar(20),diag_01 varchar(20))
	end

insert into stage.calc_tariff_19 (HRG_code, Epitype, stay_days, tariff_calc, hesid, diag_01)
	values
	(@HRG_code, @epi_type, @stay_days, @tariff, @hesid, @diag_01)

print('Results inserted in table stage.calc_tariff_19.')
go
-------------------------------------------------------------------------------------testing above stored procedure
--exec usp_tariff19_test100999 'aa22c', 11, 0

--select
--*
--from stage.calc_tariff_19 --created table

----drop table stage.calc_tariff_19


--------------------------------------------------------------------------------------------------------------------
--creating stored proc for tariffs1819 that takes a 5 column table as input, creates table with same 5 columns+ 6th column with tariff
go
alter proc usp_nhs_tariff19_table
@table_name nvarchar(max)
as

DECLARE @hrg_code varchar(5)
DECLARE @epi_type varchar(50)
Declare @stay_days int
declare @hesid varchar(20) --for identifier
declare @diag_01 varchar(20) --for identifier

if object_id('temp_table') is not null
	begin 
		drop table temp_table
	end
DECLARE @sql nvarchar(max)
	set @sql = N'SELECT * into temp_table from '+ @table_name
	exec sp_executesql @sql
if
(SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE table_catalog = 'HealthNHS' -- the database
   AND TABLE_SCHEMA = 'dbo' 
   AND table_name = 'temp_table') != 5
  begin 
		print 'Error: Input table must have four columns in order: HRG code, episode type, episode duration (days), hesid, diag_01'
		return
	end
DECLARE Test CURSOR FOR

Select
*
from temp_table

OPEN Test
 
FETCH NEXT FROM Test INTO @hrg_code, @epi_type, @stay_days, @hesid, @diag_01
 
WHILE @@FETCH_STATUS = 0
BEGIN --- iteration
 exec usp_tariff19_test100999 @hrg_code, @epi_type, @stay_days, @hesid, @diag_01
 FETCH NEXT FROM Test INTO @hrg_code, @epi_type, @stay_days , @hesid, @diag_01
END
 
CLOSE test
DEALLOCATE test
--drop table temp_table
go


---------------------------------------------------------------------------------------------------------------
--To test create table stage.test99 with all HRG codes and fake epitype and staydays, output table named stage.calc_tariff_19

--drop table stage.calc_tariff_19
--drop table stage.test999
--select distinct
--	[HRG code]
--	,'Non-elective' epitype
--	,16 stay_days
--	,'xxxxxxx' hesid
--	,'ddddd' diag_01
--into stage.test999
--from stage.tariff1819

--exec usp_nhs_tariff19_table 'stage.test999' --execute procedure with fake table

--select
--	*
--from stage.calc_tariff_19 --looks good

----drop table stage.calc_tariff_19

------------------------------------------------------------------------------------------------------------------------
--Now calculate tariff data for hes data
--first create new table with required columns

if object_id( 'hesdata') is not null
	begin drop table hesdata
	end

select
	cast(hrg_code as varchar(5)) hrg_code
	,cast(admimeth as varchar(50)) epi_type
	,cast (epidur as int) stay_days
	,hesid
	,diag_01
into hesdata
from [dbo].[HRG_and_HSe2]

----now plug into 2018-19 tariff data
--drop table stage.calc_tariff_19
--go
exec usp_nhs_tariff19_table 'dbo.hesdata'
go
--sense check results

--select
--	*
--from stage.calc_tariff_19

-- to connect back to original table ; creates query joining into new table, saving into new talbe called final.tariffs19

select
	spell, episode, epistart, epiend, h.epitype, sex, bedyear, epidur, epistat, spellbgin, activage, admiage, admincat, admincatst, category, dob, endage, ethnos, h.hesid
	, leglcat, lopatid, newnhsno, newnhsno_check, startage, admistart
	, admimeth, admisorc, elecdate, elecdur, elecdur_calc, classpat, h.diag_01, numepisodesinspell, h.HRG_code
	, c.tariff_calc
	into final.tariffs19
from [HRG_and_HSe2] h
inner join stage.calc_tariff_19 c
	on 1=1
	and h.[HRG_code] = c.hrg_code
	and h.epidur = c.stay_days
	and h.admimeth = c.epitype
	and h.hesid = c.hesid
	and h.diag_01 = c.diag_01



/******************************
Beginning section on 2017-18 tariffs
*******************************/
------------------------------------------------------------------------------------------------------------
--creating proc that takes in three seperate inputs and inserts one row into table with tariff (2017-18)
create proc usp_tariff17_test100999
--alter proc usp_tariff17_test100999
@HRG_code varchar(5), @epi_type varchar(50), @stay_days int, @hesid varchar(20), @diag_01 varchar(20)
as

if --not a good match
	@epi_type not in ('Ordinary elective','11','12','13','Non-elective','21', '25','28','2A','2B','99')
	begin
		print 'Wrong episode type input. Must input HRG code, episode type, and # of days of spell. Episode type must be one of the following: Ordinary elective, Non-elective or the ADMIMETH code from HES data'
		return
	end
Declare @tariff int
Select
@tariff = case
	when @stay_days <2 AND Reduced_emergency_tariff is not null and @epi_type like 'Non-elective' then Reduced_emergency_tariff 	
	when @stay_days <= Trim_point_days then base_price
	when @stay_days > Trim_point_days then (base_price + (@stay_days - Trim_point_days) * Long_stay_payment_per_day)
	end
from
(
Select
	case
		when @epi_type in ('Ordinary elective','11','12','13') and @stay_days = 0 then coalesce(cast([Combined day case / ordinary elective spell tariff (£)] as money),cast([Day case spell tariff (£)] as money))
		when @epi_type in ('Ordinary elective','11','12','13') and @stay_days != 0 then coalesce(cast([Combined day case / ordinary elective spell tariff (£)] as money),cast([Ordinary elective spell tariff (£)] as money))
		when @epi_type in ('Non-elective', '21', '25','28','2A','2B','99') then [Non-elective spell tariff (£)]
	end base_price
	,case
		when @epi_type in ('Ordinary elective','11','12','13') then [Ordinary elective long stay trim point (days)]
		when @epi_type in ('Non-elective', '21', '25','28','2A','2B','99') then [Non-elective long stay trim point (days)]
	end Trim_point_days
	,[Per day long stay payment (for days exceeding trim point) (£)] Long_stay_payment_per_day
	,[Reduced short stay emergency tariff (£)] Reduced_emergency_tariff
from
(	
Select
*
from stage.tariff1718
where [hrg code] like @hrg_code
) t
)p


if @tariff is null
begin
print('Tariff calculation NULL, HRG code likely not valid')
return
end

if object_id('stage.calc_tariff_17') is null
	begin 
		create table stage.calc_tariff_17 (HRG_code varchar(5), Epitype varchar(50), stay_days int, tariff_calc int, hesid varchar(20),diag_01 varchar(20))
	end

insert into stage.calc_tariff_17 (HRG_code, Epitype, stay_days, tariff_calc, hesid, diag_01)
	values
	(@HRG_code, @epi_type, @stay_days, @tariff, @hesid, @diag_01)

print('Results inserted in table stage.calc_tariff_17.')
go
-------------------------------------------------------------------------------------testing above stored procedure
--exec usp_tariff17_test100999 'aa22c', 11, 0

--select
--*
--from stage.calc_tariff_17 --created table

----drop table stage.calc_tariff_17


--------------------------------------------------------------------------------------------------------------------
--creating stored proc for tariffs1718 that takes a 5 column table as input, creates table with same 5 columns+ 6th column with tariff
go
create proc usp_nhs_tariff17_table
--alter proc usp_nhs_tariff17_table
@table_name nvarchar(max)
as

DECLARE @hrg_code varchar(5)
DECLARE @epi_type varchar(50)
Declare @stay_days int
declare @hesid varchar(20) --for identifier
declare @diag_01 varchar(20) --for identifier

if object_id('temp_table') is not null
	begin 
		drop table temp_table
	end
DECLARE @sql nvarchar(max)
	set @sql = N'SELECT * into temp_table from '+ @table_name
	exec sp_executesql @sql
if
(SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
 WHERE table_catalog = 'HealthNHS' -- the database
   AND TABLE_SCHEMA = 'dbo' 
   AND table_name = 'temp_table') != 5
  begin 
		print 'Error: Input table must have four columns in order: HRG code, episode type, episode duration (days), hesid, diag_01'
		return
	end
DECLARE Test CURSOR FOR

Select
*
from temp_table

OPEN Test
 
FETCH NEXT FROM Test INTO @hrg_code, @epi_type, @stay_days, @hesid, @diag_01
 
WHILE @@FETCH_STATUS = 0
BEGIN --- iteration
 exec usp_tariff17_test100999 @hrg_code, @epi_type, @stay_days, @hesid, @diag_01
 FETCH NEXT FROM Test INTO @hrg_code, @epi_type, @stay_days , @hesid, @diag_01
END
 
CLOSE test
DEALLOCATE test
drop table temp_table
go


---------------------------------------------------------------------------------------------------------------
--To test create table stage.test99 with all HRG codes and fake epitype and staydays, output table named stage.calc_tariff_17
--if object_id('stage.calc_tariff_17') is not null
--	begin 
--		drop table stage.calc_tariff_17
--	end

--if object_id('stage.test999') is not null
--	begin 
--		drop table stage.test999
--	end

--select distinct
--	[HRG code]
--	,'Non-elective' epitype
--	,16 stay_days
--	,'xxxxxxx' hesid
--	,'ddddd' diag_01
--into stage.test999
--from stage.tariff1718

--exec usp_nhs_tariff17_table 'stage.test999' --execute procedure with fake table

--select
--	*
--from stage.calc_tariff_17 --common sense test

--drop table stage.calc_tariff_17

------------------------------------------------------------------------------------------------------------------------
--Now calculate tariff data for hes data
--first create new table with required columns

if object_id('hesdata') is not null
	begin 
		drop table hesdata
	end

select
	cast(hrg_code as varchar(5)) hrg_code
	,cast(admimeth as varchar(50)) epi_type
	,cast (epidur as int) stay_days
	,hesid
	,diag_01
into hesdata
from [dbo].[HRG_and_HSe2]

--now plug into 2017-18 tariff data
--drop table stage.calc_tariff_17
--go
exec usp_nhs_tariff17_table 'dbo.hesdata'
go
--sense check results

--select
--	*
--from stage.calc_tariff_17

-- to connect back to original table ; creates query joining into new table, saving into new talbe called final.tariffs17

select
	spell, episode, epistart, epiend, h.epitype, sex, bedyear, epidur, epistat, spellbgin, activage, admiage, admincat, admincatst, category, dob, endage, ethnos, h.hesid
	, leglcat, lopatid, newnhsno, newnhsno_check, startage, admistart
	, admimeth, admisorc, elecdate, elecdur, elecdur_calc, classpat, h.diag_01, numepisodesinspell, h.HRG_code
	, c.tariff_calc
	into final.tariffs17
from [HRG_and_HSe2] h
inner join stage.calc_tariff_17 c
	on 1=1
	and h.[HRG_code] = c.hrg_code
	and h.epidur = c.stay_days
	and h.admimeth = c.epitype
	and h.hesid = c.hesid
	and h.diag_01 = c.diag_01




