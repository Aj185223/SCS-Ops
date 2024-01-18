set echo on
set feedback on
CREATE OR REPLACE PROCEDURE NCR_EXPLD_COMP_PROC
(errbuf             OUT VARCHAR2, 
 retcode            OUT VARCHAR2,
 p_organization_id  IN NUMBER,
 p_orig_item_id     IN NUMBER,
 p_orig_item_date   IN VARCHAR2,
 p_new_item_id      IN NUMBER,
 p_new_item_date    IN VARCHAR2,
 p_detail_summary   IN VARCHAR2)
/*                   Version: 06.02.00.01.02                                  */
/******************************************************************************/
/*   Copyright 2006 by NCR Corporation                                        */
/*   All Rights Reserved                                                      */
/*                                                                            */
/*  Project:            ERP                                                   */
/*  File :              bom_expld_comp_proc.sql                               */
/*  File Type:          Stored procedure                                      */
/*  Program Full Name:  NCR BOM Comparison and Action List                    */
/*  Program Short Name: NCRBOMCP                                              */
/*                                                                            */
/*   Description:           FSD need a new report which will compare the      */
/*                          bills of material for two configured products     */
/*                          and identify which parts can be removed or added  */
/*                          based on the comparison. The report should allow  */
/*                          the data to be extracted to a spreadsheet. It     */
/*                          will allow the user to enter the Original and New */
/*                          Product ids to compare, and explode their         */
/*                          corresponding bills of material to the lowest     */
/*                          level, or to a level at which the component is a  */
/*                          buy item. A comparison will take place and the    */
/*                          report will display those low level components or */
/*                          raw material requirement quantities which differ  */
/*                          and indicate an instruction as to whether the     */
/*                          quantities should be added or removed from the    */
/*                          new product.                                      */
/*   Called from:           Oracle Bills of Material - Submit: Request        */
/*   Executes:              N/A                                               */
/*                                                                            */
/*   Parameters:            Original Product ID                IN             */
/*                          Original Product Effectivity Date  IN             */
/*                          New Product ID                     IN             */
/*                          New Product Effectivity Date       IN             */
/*                          Organization                       IN             */
/*                          Detail or Summary View             IN             */
/*                                                                            */
/*  Date of      Author of         Change    Comments/Description             */
/*  Change       Change            Ref.      of Change                        */
/*  -------      ---------         ------    ------------------------------   */
/*  10-OCT-2006  Fred Richards     N/A        Release 3.5                     */
/*  02-JAN-2007  Fred Richards     RFC 1774   Add Parent Item when Component  */
/*                                            Item displays  sum quantities   */
/*                                            accordingly                     */
/*  02-MAR-2007  Fred Richards     RFC 2262   Compare Procudts by Revision    */
/*                                            Effectivity Date                */
/*                                            Add Summary View                */
/*  08-MAR-2007  Fred Richards     TAR 345938 Remove Buy Level Items that     */
/*                                            occur beneath other Buy Level   */
/*                                            Items                           */
/*  09-MAR-2007  Fred Richards     TAR 346104 Remove Buy Level Items that     */
/*                                            occur beneath Sub-assemblies    */
/*                                                                            */
/*  13-MAR-2007  Ajay Singh        TAR  346300 Flow Item BOM Compare program  */
/*                                             Prints Items with 0 quantities */
/*  02-APR-2007  Amit Srivastava   Tar  347294 BOM Compare is not Using       */
/*                                             Effective Dates Properly.      */
/*  16-APR-2007  Amit Srivastava   TAR 348916  BOM Compare - Summary Version  */
/*                                              not Matching Detail Version   */
/*  18-July-2007  Neelesh Jain     TAR 352136  The effectivity date does not  */
/*                                         working properly for bom_comprasion*/
/*  09-Oct-2007   Neelesh Jain     TAR 361014  displays the Supply Location as*/
/*                                             user defined location name     */
/*  17-Jan-2007  Neelesh Jain      Rfc#3296  Report to look at UN-IMPLEMENTED */
/*                                           BOM with  IMPLEMENTED BOM        */ 
/*  23-Jan-2008  Neelesh Jain     TAR#368168  Display record's for ECO's which*/
/*                                       implemented and not implemented       */
/* 21-OCT-2009   DS185042         Tar #418662 NCR BOM Comarison  Action List   */
/*                                            missing components               */
/* 23-JAN-2012   SV250113         1128.1048.03 ERP Release 12 Upgrade retrofits*/
/* 27-MAR-2012   Rajiv Sharma      ERP-3127     Code fix to avoid listing of   */
/*                                            duplicate components in the      */
/*                                            report output.                   */
/* 09-DEC-2013   PK185121        JIRA#ERP_GCA-2660 STANDARD item included      */
/*                                             while comparision of BOMS       */
/* 04-AUG-14 SB185061 MPM_MFG_1135_PN3745_F002-Modify for IBB Project         */
/*                             to support new BOM Structure CID as components  */
/* 11-SEP-14 SB185061  JIRA#ERP-8887 Modify to fix the incorrect components    */
/*                              issue in the 6691 subclsss                     */
/* 19-SEP-14 SB185061  JIRA#ERP-8994 Added a logic to show the FSD Make item in*/ 
/*                     report output                                           */       
/*******************************************************************************/

AS
    v_org_code           MTL_PARAMETERS.ORGANIZATION_ID%TYPE;
    v_orig_item          MTL_SYSTEM_ITEMS_B.SEGMENT1%TYPE;    --Product ID; Items form - Item Field
    v_new_item           MTL_SYSTEM_ITEMS_B.SEGMENT1%TYPE;    --Product ID; Items form - Item Field

    -- RFC 1774
    v_par_item           MTL_SYSTEM_ITEMS_B.SEGMENT1%TYPE;    --Product ID; Items form - Item Field

    v_orig_item_id       MTL_SYSTEM_ITEMS_B.INVENTORY_ITEM_ID%TYPE;  --Item ID
    v_new_item_id        MTL_SYSTEM_ITEMS_B.INVENTORY_ITEM_ID%TYPE;  --Item ID

    -- RFC 2262
    v_orig_item_date     MTL_ITEM_REVISIONS_B.EFFECTIVITY_DATE%TYPE;  --Original Item Revision Effectivity Date
    v_new_item_date      MTL_ITEM_REVISIONS_B.EFFECTIVITY_DATE%TYPE;  --New Item Revision Effectivity Date

    v_orig_item_rev      MTL_ITEM_REVISIONS_B.REVISION%TYPE;  --Item Revision
    v_new_item_rev       MTL_ITEM_REVISIONS_B.REVISION%TYPE;  --Item Revision

    -- RFC 2262
    v_detail_summary     VARCHAR2(1) := '1';  --Detail (1) or Summary (2) View

    v_cnt                NUMBER      := 0;
    v_curr_action        VARCHAR2(3) := NULL;
    v_expl_action        VARCHAR2(3) := NULL;
    v_action_qty         NUMBER      := 0;
    v_include            BOOLEAN     := TRUE;  -- TAR 345938
    v_segment1           mtl_item_locations.segment1%type:=null;--- add against star tar 361014
    v_par_item_id        MTL_SYSTEM_ITEMS_B.INVENTORY_ITEM_ID%TYPE   :=NULL;  -- TAR 345938
    v_cpnt_code          BOM_EXPLOSION_TEMP.COMPONENT_CODE%TYPE   :=NULL;  -- TAR 345938

    v_user_id            FND_USER.USER_ID%TYPE             := FND_GLOBAL.USER_ID;
    v_login_id           FND_USER.LAST_UPDATE_LOGIN%TYPE   := FND_GLOBAL.LOGIN_ID;
    v_bompexpl_err       EXCEPTION;

    -- variables for BOM Explosion procedure bompexpl.exploder_userexit --
    v_err_msg            VARCHAR2(50);
    v_err_code           NUMBER := 0;
    v_verify_flag        NUMBER := 0;            -- DEFAULT 0
    v_order_by           NUMBER := 1;            -- DEFAULT 1
    v_alternate          VARCHAR2(240) := NULL;  -- DEFAULT NULL
    v_orig_grp_id        NUMBER := 0;
    v_new_grp_id         NUMBER := 0;
    v_session_id         NUMBER := 0;
    v_levels_to_explode  NUMBER := 1;            -- DEFAULT 1
    v_bom_or_eng         NUMBER := 1;            -- DEFAULT 1
   -- v_impl_flag        NUMBER := 1;            -- DEFAULT 1
    v_impl_flag          NUMBER := 2;            -- DEFAULT 2 --Changes against rfc#3296
    v_plan_factor_flag   NUMBER := 2;            -- DEFAULT 2
    v_explode_option     NUMBER := 2;            -- DEFAULT 2
    v_module             NUMBER := 2;            -- DEFAULT 2
    v_cst_type_id        NUMBER := 0;            -- DEFAULT 0
    v_std_comp_flag      NUMBER := 0;            -- DEFAULT 0
    v_expl_qty           NUMBER := 1;            -- DEFAULT 1
    v_comp_code          VARCHAR2(240) := NULL;  -- DEFAULT NULL
    v_rev_date           VARCHAR2(240);
    v_unit_number        VARCHAR2(250) := ''; --Added for Req#1128.1048.03
    v_release_option     NUMBER := 0;         --Added for Req#1128.1048.03
    v_item_type          MTL_SYSTEM_ITEMS_B.ITEM_TYPE%TYPE; -- Added for the JIRA#ERP-8887

BEGIN

    v_org_code := p_organization_id;     --Capture Organization ID parameter into a variable
    v_orig_item_id := p_orig_item_id ;   --Capture Organization ID parameter into a variable
    v_new_item_id := p_new_item_id ;     --Capture Organization ID parameter into a variable

    -- RFC 2262
    v_detail_summary := p_detail_summary;  --Capture Detail/Summary parameter into a variable
   -- v_orig_item_date := TO_DATE(p_orig_item_date,'YYYY-MM-DD HH24:MI:SS');--'YYYY/MM/DD HH24:MI:SS');  --Commented against star tar 352136 Capture Original --Itam Rev Date parameter into a variable
   -- v_new_item_date  := TO_DATE(p_new_item_date,'YYYY-MM-DD HH24:MI:SS');--'YYYY/MM/DD HH24:MI:SS');   --Commented against star tar 352136 Capture New --Item Rev Date parameter into a variable

   v_orig_item_date := TO_DATE(p_orig_item_date,'YYYY/MM/DD HH24:MI:SS');  --Added  against star tar 352136 
   v_new_item_date  := TO_DATE(p_new_item_date,'YYYY/MM/DD HH24:MI:SS');   --Added  against star tar 352136


     FND_FILE.PUT_LINE(FND_FILE.LOG,'Orginial Date :-'|| v_orig_item_date);
     FND_FILE.PUT_LINE(FND_FILE.LOG,'New Date :-'|| v_new_item_date);


    -- Capture Original Item ID for use in Explosion routine --
    SELECT SEGMENT1
    INTO   v_orig_item
    FROM   MTL_SYSTEM_ITEMS_B
    WHERE  INVENTORY_ITEM_ID = v_orig_item_id
    AND    ORGANIZATION_ID = v_org_code;

    -- Capture Original Item Revision --
    SELECT r.REVISION
    INTO   v_orig_item_rev
    FROM   MTL_ITEM_REVISIONS_B r
    WHERE  r.INVENTORY_ITEM_ID = v_orig_item_id
    AND    r.ORGANIZATION_ID = v_org_code
    AND    r.EFFECTIVITY_DATE = (SELECT MAX(v.EFFECTIVITY_DATE)
                                   FROM MTL_ITEM_REVISIONS_B v
                                  WHERE v.INVENTORY_ITEM_ID = v_orig_item_id
                                    AND v.ORGANIZATION_ID = v_org_code
                                    AND v.EFFECTIVITY_DATE <= v_orig_item_date);  -- RFC 2262

    -- Capture New Item ID for use in Explosion routine --
    SELECT SEGMENT1
    INTO   v_new_item
    FROM   MTL_SYSTEM_ITEMS_B
    WHERE  INVENTORY_ITEM_ID = v_new_item_id
    AND    ORGANIZATION_ID = v_org_code;

    -- Capture New Item Revision --
    SELECT r.REVISION
    INTO   v_new_item_rev
    FROM   MTL_ITEM_REVISIONS_B r
    WHERE  r.INVENTORY_ITEM_ID = v_new_item_id
    AND    r.ORGANIZATION_ID = v_org_code
    AND    r.EFFECTIVITY_DATE = (SELECT MAX(v.EFFECTIVITY_DATE)
                                   FROM MTL_ITEM_REVISIONS_B v
                                  WHERE v.INVENTORY_ITEM_ID = v_new_item_id
                                    AND v.ORGANIZATION_ID = v_org_code
                                    AND v.EFFECTIVITY_DATE <= v_new_item_date);  -- RFC 2262

    -- Capture Maximum BOM Level for use in Explosion routine --
    SELECT MAX(MAXIMUM_BOM_LEVEL)
    INTO   v_levels_to_explode
    FROM   BOM_PARAMETERS
    WHERE  ORGANIZATION_ID= p_organization_id;

   -- v_rev_date := to_char(SYSDATE);

  v_rev_date := to_char(v_orig_item_date,'YYYY-MM-DD HH24:MI:SS');--Added  against star tar 352136
    -- Session ID is a unique value to identify current session --
    SELECT BOM_EXPLOSION_TEMP_SESSION_S.NEXTVAL INTO v_session_id FROM DUAL;
    -- Group_ID is a unique value to identify current (Original Item) explosion --
    SELECT BOM_EXPLOSION_TEMP_S.NEXTVAL INTO v_orig_grp_id FROM DUAL;
   FND_FILE.PUT_LINE(FND_FILE.LOG,'group id for orginal item bom explosion is' || v_orig_grp_id);

    -- Call BOM Exploder routine to Explode the Original Item --
     --insert into BOM_EXPLOSION_TEMP2 as select * from 
    APPS.BOMPEXPL.EXPLODER_USEREXIT (
      v_verify_flag,
      v_org_code,
      v_order_by,
      v_orig_grp_id,
      v_session_id,
      v_levels_to_explode,
      v_bom_or_eng,
      v_impl_flag,
      v_plan_factor_flag,
      v_explode_option,
      v_module,
      v_cst_type_id,
      v_std_comp_flag,
      v_expl_qty,
      v_orig_item_id,
      v_alternate,
      v_comp_code,
      v_rev_date,
      v_unit_number,    --Added for Req#1128.1048.03
      v_release_option, --Added for Req#1128.1048.03
      v_err_msg,
      v_err_code);
      
    --  insert into bom_explosions_temp1 
    --       select * from BOM_EXPLOSION_TEMP;
    -- commit;

    ---fnd_file.put_line(fnd_file.log,'New Group is'  || v_orig_grp_id);

    IF (v_err_code <> 0) THEN
      RAISE v_bompexpl_err;
    END IF;
    v_rev_date := to_char(v_new_item_date,'YYYY-MM-DD HH24:MI:SS');--Added  against star tar 352136
--     v_rev_date := to_char(SYSDATE);
     -- Group_ID is a unique value to identify current (New Item) explosion --
  SELECT BOM_EXPLOSION_TEMP_S.NEXTVAL INTO v_new_grp_id FROM DUAL;

  FND_FILE.PUT_LINE(FND_FILE.LOG,' New Group id  new item bom explosion is'  || v_new_grp_id);

    -- Call BOM Exploder routine to Explode the New Item --
       APPS.BOMPEXPL.EXPLODER_USEREXIT (
      v_verify_flag,
      v_org_code,
      v_order_by,
      v_new_grp_id,
      v_session_id,
      v_levels_to_explode,
      v_bom_or_eng,
      v_impl_flag,
      v_plan_factor_flag,
      v_explode_option,
      v_module,
      v_cst_type_id,
      v_std_comp_flag,
      v_expl_qty,
      v_new_item_id,
      v_alternate,
      v_comp_code,
      v_rev_date,
      v_unit_number,    --Added for Req#1128.1048.03
      v_release_option, --Added for Req#1128.1048.03
      v_err_msg,
      v_err_code);

--insert into bom_explosions_temp1 
--           select * from BOM_EXPLOSION_TEMP;
--     commit;
 
--fnd_file.put_line(fnd_file.log,'New Group is'  || v_new_grp_id);
    IF (v_err_code <> 0) THEN
      RAISE v_bompexpl_err;
    END IF;

  -- Add Session Id to BOM_EXPLOSION_TEMP; the Explosion routine does not properly set this --

   -- fnd_file.put_line(fnd_file.log,'session id is '|| v_session_id );

  UPDATE BOM_EXPLOSION_TEMP SET SESSION_ID = v_session_id;

   commit;

   
  -- fnd_file.put_line(fnd_file.log,'session id is '|| v_session_id );

  -- Loop applicable records from Explosion table, per query --

  FOR it_rec in(SELECT f.GROUP_ID,
                       f.ORGANIZATION_ID,
                       f.ASSEMBLY_ITEM_ID,  -- RFC 1774
                       f.TOP_ITEM_ID,  -- TAR 345938
                       f.COMPONENT_ITEM_ID,  -- TAR 345938
                       f.COMPONENT_CODE,  -- TAR 345938
                       m.SEGMENT1,
                       r.REVISION,
                       f.EXTENDED_QUANTITY,
                       t.DESCRIPTION,
                       m.PLANNER_CODE,
                       m.WIP_SUPPLY_SUBINVENTORY,
                       m.WIP_SUPPLY_LOCATOR_ID,
                       m.PLANNING_MAKE_BUY_CODE ,
                       m.item_type   -- Added for JIRA#ERP-8887
                  FROM MTL_SYSTEM_ITEMS_B m,
                       MTL_ITEM_REVISIONS_B r,
                       MTL_SYSTEM_ITEMS_TL t,
                      --BOM_EXPLOSIONS_TEMP1 f
                       BOM_EXPLOSION_TEMP f
                 WHERE m.INVENTORY_ITEM_ID = f.COMPONENT_ITEM_ID
                   AND m.ORGANIZATION_ID = f.ORGANIZATION_ID
                   AND(( m.PLANNING_MAKE_BUY_CODE = 2
                         --AND m.ITEM_TYPE IN ('FSD BUY RAW MAT')   -- Production
                         AND m.ITEM_TYPE IN ('FSD BUY RAW MAT',     -- For testing in Delta
                                             'RAW MATERIAL',
                                             'SMD RAW MATERIAL','STANDARD'))   -----Code Modified by PK185121 Against JIRA ERP_GCA-2660
                      OR
                       (m.PLANNING_MAKE_BUY_CODE=1     --OR clause added as part of requirement MPM_MFG_1135_PN3745_F002 to support Child CID
                        AND m.ITEM_TYPE IN ('CID','FSD MAKE SUBASSY')))   --Added "FSD MAKE SUBASSY" for the JIRA#ERP-8994
                   AND t.INVENTORY_ITEM_ID = f.COMPONENT_ITEM_ID
                   AND t.ORGANIZATION_ID = f.ORGANIZATION_ID
                  -- AND NVL(f.EFFECTIVITY_DATE, SYSDATE - 1) BETWEEN TO_DATE(p_orig_item_date,'YYYY-MM-DD HH24:MI:SS') --SYSDATE STARTAR347294
                  --   AND TO_DATE(p_new_item_date,'YYYY-MM-DD HH24:MI:SS')
                  --   AND NVL(f.IMPLEMENTATION_DATE, SYSDATE - 1) < TO_DATE(p_new_item_date,'YYYY-MM-DD HH24:MI:SS') --SYSDATE STARTAR347294
                  --    AND NVL(f.DISABLE_DATE, SYSDATE + 1) > SYSDATE 
                  --AND NVL(f.EFFECTIVITY_DATE, SYSDATE - 1) < SYSDATE -- newly changes against star tar #368168  
  --  AND NVL(f.IMPLEMENTATION_DATE, SYSDATE - 1) < SYSDATE -- newly changes against star tar #368168  
                --   AND NVL(f.DISABLE_DATE, SYSDATE + 1) > SYSDATE-- newly changes against star tar #368168  
                   AND r.INVENTORY_ITEM_ID = f.COMPONENT_ITEM_ID
                   AND r.ORGANIZATION_ID = v_org_code
                   AND f.ASSEMBLY_ITEM_ID IS NOT NULL	 --Modified for MPM_MFG_1135_PN3745_F002 to exclude top CID Assembly
-- Added against STAR Tar 346300
-- The BOM Compare and Action List Program is printing components with 0
                   AND f.EXTENDED_QUANTITY <>0
                   AND r.EFFECTIVITY_DATE = (SELECT MAX(v.EFFECTIVITY_DATE)
                                             FROM MTL_ITEM_REVISIONS_B v
                                             WHERE v.INVENTORY_ITEM_ID = f.COMPONENT_ITEM_ID
                                             AND v.ORGANIZATION_ID = v_org_code
                                             --AND v.EFFECTIVITY_DATE <= DECODE(f.TOP_ITEM_ID, v_orig_item_id, v_orig_item_date, v_new_item_date)))  -- RFC 2262
                                             -- Comment out the the Above statement for Tar # 418662 -20 OCT-2009
                                              AND v.EFFECTIVITY_DATE <= DECODE(f.GROUP_ID, v_orig_grp_id, v_orig_item_date, v_new_item_date)))  --Tar # 418662 -20 OCT-2009
 
  LOOP

     --Capture Parent Item ID --
    -- TAR 345938 - TAR 346104 - Begin
    v_par_item_id := it_rec.ASSEMBLY_ITEM_ID;
    v_include     := TRUE;
    v_cpnt_code   := SUBSTR(it_rec.COMPONENT_CODE, 1, LENGTH(it_rec.COMPONENT_CODE) - LENGTH(it_rec.COMPONENT_ITEM_ID) - 1);
    WHILE v_par_item_id <> it_rec.TOP_ITEM_ID LOOP
      -- Determine if Item is Buy or Sub-assembly --
       SELECT COUNT(*)
       INTO v_cnt
       FROM MTL_SYSTEM_ITEMS_B
       WHERE INVENTORY_ITEM_ID = v_par_item_id
       AND ORGANIZATION_ID = v_org_code
       AND ITEM_TYPE IN ('FSD BUY RAW MAT',   -- Production
                        'FSD MAKE SUBASSY','CID');	-- Modified for MPM_MFG_1135_PN3745_F002 to pickup CID item type
         --AND ITEM_TYPE IN ('FSD BUY RAW MAT',     -- For testing in Delta
         --                  'RAW MATERIAL',
         --                  'SMD RAW MATERIAL',
         --                  'FSD MAKE SUBASSY',
         --                  'FSD PHANTOM SUBASSY',
         --                  'SUBASSEMBLY');

   FND_FILE.PUT_LINE(FND_FILE.LOG,'count for Item that is Buy or Sub-assembly '||v_cnt  );
   IF v_cnt > 0 THEN
      v_include     := FALSE;
      v_par_item_id := it_rec.TOP_ITEM_ID;
      fnd_file.put_line(fnd_file.log,'new top item id is '||v_par_item_id );
   ELSE
       IF LENGTH(v_cpnt_code) = LENGTH(it_rec.TOP_ITEM_ID) THEN
          v_par_item_id := it_rec.TOP_ITEM_ID;
        ELSE
          v_cpnt_code   := SUBSTR(v_cpnt_code, 1, LENGTH(v_cpnt_code) - LENGTH(v_par_item_id) - 1);

          IF LENGTH(v_cpnt_code) = LENGTH(it_rec.TOP_ITEM_ID) THEN
            v_par_item_id := it_rec.TOP_ITEM_ID;
          ELSE
            v_par_item_id := TO_NUMBER(SUBSTR(v_cpnt_code, INSTR(v_cpnt_code, '-', -1, 1) + 1));
          END IF;
     END IF;
   END IF;
  END LOOP; -- End of  While loop 
    -- TAR 345938 - ??? ?????? - End
  IF v_include THEN  -- TAR 345938 - END
      -- Capture Parent Product ID --
      -- RFC 1774 - Begin
      SELECT SEGMENT1
      INTO   v_par_item
      FROM   MTL_SYSTEM_ITEMS_B
      WHERE  INVENTORY_ITEM_ID = it_rec.ASSEMBLY_ITEM_ID
      AND    ORGANIZATION_ID = v_org_code;
      -- RFC 1774 - End
      --  Check for a Match on Component and Parent Item ID --
      IF v_detail_summary = '1' THEN  -- RFC 2262
      -- Detail --
      
         -- Added for JIRA#ERP-8887
       IF it_rec.item_type='CID'  THEN
        SELECT COUNT(*)
        INTO   v_cnt
        FROM   NCR_EXPLODED_BOM_ITEMS
        WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
        AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
        AND    COMP_ITEM_REV = it_rec.REVISION  
        AND    SESSION_ID  = v_session_id; 
        ELSIF  it_rec.item_type<>'CID' THEN  -- Added for JIRA#ERP-8887
        SELECT COUNT(*)
        INTO   v_cnt
        FROM   NCR_EXPLODED_BOM_ITEMS
        WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
        AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
        AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
        AND    PAR_ITEM_ID = v_par_item   -- RFC 1774
        AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
      END IF; -- Added for JIRA#ERP-8887
      ELSE
      -- Summary --
        SELECT COUNT(*)
        INTO   v_cnt
        FROM   NCR_EXPLODED_BOM_ITEMS
        WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
        AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
        AND    COMP_ITEM_REV = it_rec.REVISION   -- RFC 2262
        AND    SESSION_ID    = v_session_id;    --Added for ERP-3127
      END IF;
     IF v_cnt = 0 THEN  -- No Matching Record exists in NCR_EXPLODED_BOM_ITEMS --
        -- Insert New Record --
        fnd_file.put_line(fnd_file.log,'insert count on NCR_EXPLODED_BOM_ITEMS '|| v_cnt);

        INSERT INTO NCR_EXPLODED_BOM_ITEMS
          (SESSION_ID,
           ORGANIZATION_ID,
           ORIG_ITEM_ID,
           ORIG_ITEM_REV,
           NEW_ITEM_ID,
           NEW_ITEM_REV,
           PAR_ITEM_ID,  -- RFC 1774
           COMP_ITEM_ID,
           COMP_ITEM_REV,
           DESCRIPTION,
           PLANNER_CODE,
           ACTION,-- Neelesh
           ACTION_QTY,
           WIP_SUPPLY_SUBINVENTORY,
           WIP_SUPPLY_LOCATOR_ID,
           MAKE_BUY,
           ATTRIBUTE1,
           ATTRIBUTE2,
           ATTRIBUTE3,
           ATTRIBUTE4,
           ATTRIBUTE5,
           CREATION_DATE,
           CREATED_BY,
           LAST_UPDATE_LOGIN,
           LAST_UPDATE_DATE,
           LAST_UPDATED_BY)
        VALUES
          (v_session_id,
           v_org_code,
           v_orig_item,
           v_orig_item_rev,
           v_new_item,
           v_new_item_rev,
           v_par_item,      -- RFC 1774
           it_rec.SEGMENT1,
           it_rec.REVISION,
           it_rec.DESCRIPTION,
           it_rec.PLANNER_CODE,
          DECODE(it_rec.GROUP_ID, v_orig_grp_id, 'DEL', 'ADD'), --Neelesh
           it_rec.EXTENDED_QUANTITY,
           it_rec.WIP_SUPPLY_SUBINVENTORY,
           it_rec.WIP_SUPPLY_LOCATOR_ID,
           DECODE(it_rec.PLANNING_MAKE_BUY_CODE, 1, 'Make', 'Buy'),
           NULL, NULL, NULL, NULL, NULL,
           SYSDATE,
           v_user_id,
           v_login_id,
           SYSDATE,
           v_user_id);
      ELSE  -- A Matching Record exists in NCR_EXPLODED_BOM_ITEMS --

      IF v_detail_summary = '1' THEN  -- RFC 2262
      -- Detail --
              --Added for JIRA#ERP-8887
         IF it_rec.ITEM_TYPE='CID'  THEN
          -- Capture ACTION and ACTION_QTY for Components having CID item --
          SELECT ACTION, ACTION_QTY 
          INTO   v_curr_action, v_action_qty
          FROM  NCR_EXPLODED_BOM_ITEMS 
          WHERE  COMP_ITEM_ID =it_rec.SEGMENT1
          AND   ORGANIZATION_ID = it_rec.ORGANIZATION_ID
          AND    COMP_ITEM_REV = it_rec.REVISION
          AND    SESSION_ID  = v_session_id ; 
          ELSIF  it_rec.ITEM_TYPE<>'CID' THEN  --Added for JIRA#ERP-8887
          -- Capture ACTION and ACTION_QTY from the Existing Record --
          SELECT ACTION, ACTION_QTY
          INTO   v_curr_action, v_action_qty
          FROM   NCR_EXPLODED_BOM_ITEMS
          WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
          AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
          AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
          AND    PAR_ITEM_ID = v_par_item  -- RFC 1774
          AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
        END IF; --Added for JIRA#ERP-8887

          -- Capture Explosion Record Action -- Neelesh
          IF it_rec.GROUP_ID = v_orig_grp_id THEN
            v_expl_action := 'DEL';
          ELSE
            v_expl_action := 'ADD';
          END IF;
          
          
          --fnd_file.put_line(fnd_file.log,'GROUP_ID is '|| v_orig_grp_id);
          
          --fnd_file.put_line(fnd_file.log,' adding or deleting Record '||  v_expl_action);
                  

          -- Existing Record Action = Explosion Record Action  --
          -- Action Remains the same and Action Qtys are added --
          IF v_curr_action = v_expl_action THEN
            --Added for JIRA#ERP-8887
            IF it_rec.ITEM_TYPE='CID'  THEN
            UPDATE NCR_EXPLODED_BOM_ITEMS SET
                   ACTION_QTY = it_rec.EXTENDED_QUANTITY + v_action_qty
            WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION  
            AND    SESSION_ID  = v_session_id;  
            ELSIF  it_rec.ITEM_TYPE<>'CID' THEN --Added for JIRA#ERP-8887
            UPDATE NCR_EXPLODED_BOM_ITEMS SET
                   ACTION_QTY = it_rec.EXTENDED_QUANTITY + v_action_qty
            WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
            AND    PAR_ITEM_ID = v_par_item  -- RFC 1774
            AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
            END IF; --Added for JIRA#ERP-8887
            ----Added for JIRA#ERP-8887
            IF it_rec.ITEM_TYPE='CID' THEN
            SELECT ACTION_QTY  
            INTO   v_action_qty
            FROM   NCR_EXPLODED_BOM_ITEMS
            WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION
            AND    SESSION_ID  = v_session_id; 
            ELSIF   it_rec.ITEM_TYPE<>'CID' THEN  --Added for JIRA#ERP-8887
            SELECT ACTION_QTY  -- --STARTAR 348916
            INTO   v_action_qty
            FROM   NCR_EXPLODED_BOM_ITEMS
            WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION
            AND    PAR_ITEM_ID = v_par_item
            AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
            END IF;    --Added for JIRA#ERP-8887

            IF v_action_qty =0 THEN --STARTAR 348916
               --Added for JIRA#ERP-8887
              IF it_rec.ITEM_TYPE='CID' THEN
                DELETE FROM  NCR_EXPLODED_BOM_ITEMS
                WHERE    ACTION_QTY = 0
                AND   COMP_ITEM_ID = it_rec.SEGMENT1
                AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
                AND    COMP_ITEM_REV = it_rec.REVISION
                AND    SESSION_ID  = v_session_id;  
                ELSIF   it_rec.ITEM_TYPE<>'CID' THEN  --Added for JIRA#ERP-8887
                DELETE FROM  NCR_EXPLODED_BOM_ITEMS
                WHERE    ACTION_QTY = 0
                AND   COMP_ITEM_ID = it_rec.SEGMENT1
                AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
                AND    COMP_ITEM_REV = it_rec.REVISION
                AND    PAR_ITEM_ID = v_par_item
                AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
                END IF;  --Added for JIRA#ERP-8887
            commit;
            END IF;
          -- Existing Record Action <> Explosion Record Action --
          ELSE

            -- If Action Qty = Explosion Record Extended Qty; Delete the record --
            IF v_action_qty = it_rec.EXTENDED_QUANTITY  THEN
              --Added for JIRA#ERP-8887
              IF it_rec.ITEM_TYPE='CID' THEN
              DELETE FROM NCR_EXPLODED_BOM_ITEMS
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  
              AND    SESSION_ID  = v_session_id;  
              ELSIF  it_rec.ITEM_TYPE<>'CID' THEN  --Added for JIRA#ERP-8887
              DELETE FROM NCR_EXPLODED_BOM_ITEMS
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    PAR_ITEM_ID = v_par_item  -- RFC 1774
              AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
              END IF;    --Added for JIRA#ERP-8887

            -- If Action Qty > Explosion Record Extended Qty          --
            -- Subtract Explosion Record Extended Qty from Action Qty --
            -- Action Remains the same                                --
            ELSIF v_action_qty > it_rec.EXTENDED_QUANTITY THEN
               --Added for JIRA#ERP-8887
              IF it_rec.ITEM_TYPE='CID' THEN
              UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION_QTY = v_action_qty - it_rec.EXTENDED_QUANTITY
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  
              AND    SESSION_ID  = v_session_id;  
              ELSIF   it_rec.ITEM_TYPE<>'CID' THEN  --Added for JIRA#ERP-8887
              UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION_QTY = v_action_qty - it_rec.EXTENDED_QUANTITY
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    PAR_ITEM_ID = v_par_item  -- RFC 1774
              AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
              END IF; --Added for JIRA#ERP-8887

            -- If Action Qty < Explosion Record Extended Qty           --
            -- Subtract Action Qty from Explosion Record Extended Qty  --
            -- Action becomes Explosion Record Action                  --
            ELSE
             --Added for JIRA#ERP-8887
            IF   it_rec.ITEM_TYPE='CID' THEN
            UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION = v_expl_action,
                     ACTION_QTY = it_rec.EXTENDED_QUANTITY - v_action_qty
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  
              AND    SESSION_ID  = v_session_id;  
            ELSIF  it_rec.ITEM_TYPE<>'CID' THEN --Added for JIRA#ERP-8887
              UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION = v_expl_action,
                     ACTION_QTY = it_rec.EXTENDED_QUANTITY - v_action_qty
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    PAR_ITEM_ID = v_par_item  -- RFC 1774
              AND    SESSION_ID  = v_session_id;  --Added for ERP-3127
              END IF;     --Added for JIRA#ERP-8887

            END IF;

          END IF;

        ELSE
        -- Summary --

          -- Capture ACTION and ACTION_QTY from the Existing Record --
          SELECT ACTION, ACTION_QTY
          INTO   v_curr_action, v_action_qty
          FROM   NCR_EXPLODED_BOM_ITEMS
          WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
          AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
          AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
          AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

          -- Capture Explosion Record Action -- Neelesh
          IF it_rec.GROUP_ID = v_orig_grp_id THEN
            v_expl_action := 'DEL';
          ELSE
            v_expl_action := 'ADD';
          END IF;
      
         -- Existing Record Action = Explosion Record Action  --
          -- Action Remains the same and Action Qtys are added --
          IF v_curr_action = v_expl_action THEN
            UPDATE NCR_EXPLODED_BOM_ITEMS SET
                   ACTION_QTY = it_rec.EXTENDED_QUANTITY + v_action_qty
            WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
            AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

            SELECT ACTION_QTY  --STARTAR347294
            INTO   v_action_qty
            FROM   NCR_EXPLODED_BOM_ITEMS
            WHERE   COMP_ITEM_ID = it_rec.SEGMENT1
            AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
            AND    COMP_ITEM_REV = it_rec.REVISION
            AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

           IF v_action_qty =0 THEN --STARTAR347294
                DELETE FROM  NCR_EXPLODED_BOM_ITEMS
                WHERE    ACTION_QTY = 0
                AND   COMP_ITEM_ID = it_rec.SEGMENT1
                AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
                AND    COMP_ITEM_REV = it_rec.REVISION
                AND    SESSION_ID    = v_session_id;  --Added for ERP-3127
            commit;
            END IF;

          -- Existing Record Action <> Explosion Record Action --
          ELSE

            -- If Action Qty = Explosion Record Extended Qty; Delete the record --
            IF v_action_qty = it_rec.EXTENDED_QUANTITY  THEN
              DELETE FROM NCR_EXPLODED_BOM_ITEMS
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

            -- If Action Qty > Explosion Record Extended Qty          --
            -- Subtract Explosion Record Extended Qty from Action Qty --
            -- Action Remains the same                                --
            ELSIF v_action_qty > it_rec.EXTENDED_QUANTITY THEN
              UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION_QTY = v_action_qty - it_rec.EXTENDED_QUANTITY
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

            -- If Action Qty < Explosion Record Extended Qty           --
            -- Subtract Action Qty from Explosion Record Extended Qty  --
            -- Action becomes Explosion Record Action                  --
            ELSE
              UPDATE NCR_EXPLODED_BOM_ITEMS SET
                     ACTION = v_expl_action,
                     ACTION_QTY = it_rec.EXTENDED_QUANTITY - v_action_qty
              WHERE  COMP_ITEM_ID = it_rec.SEGMENT1
              AND    ORGANIZATION_ID = it_rec.ORGANIZATION_ID
              AND    COMP_ITEM_REV = it_rec.REVISION  -- RFC 2262
              AND    SESSION_ID    = v_session_id;  --Added for ERP-3127

            END IF;

          END IF;

        END IF;

      END IF;

    END IF;  -- TAR 345938

  END LOOP;

  -- Write Contents of NCR_EXPLODED_BOM_ITEMS to Output file --
  -- Check for Data in NCR_EXPLODED_BOM_ITEMS --
  SELECT COUNT(*)
  INTO   v_cnt
  FROM   NCR_EXPLODED_BOM_ITEMS
  WHERE  SESSION_ID = v_session_id;  --Added for ERP-3127

  IF v_cnt = 0 THEN  -- No Records exists; Write out exception --
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
    '********* Original Product Bill is same as New Product Bill *********');
  ELSE  -- Data Exists

    IF v_detail_summary = '1' THEN  -- RFC 2262
    -- Detail --

      -- Headers --
      FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
        'Original Product'       ||'|'||
        'Rev'                    ||'|'||
        'New Product'            ||'|'||
        'Rev'                    ||'|'||
        'Action'                 ||'|'||
        'Raw Material'           ||'|'||
        'Rev'                    ||'|'||
        'Description'            ||'|'||
        'Planner Code'           ||'|'||
        'Action Quantity'        ||'|'||
        'Parent Assembly'        ||'|'||  -- RFC 1774
        'Supply Subinventory'    ||'|'||
        'Supply Location'        ||'|'||
        'Make/Buy');

      -- Data --
    --FOR out_rec in(SELECT * FROM NCR_EXPLODED_BOM_ITEMS)  --Commented for ERP-3127
      FOR out_rec in(SELECT * FROM NCR_EXPLODED_BOM_ITEMS WHERE SESSION_ID = v_session_id)  --Added for ERP-3127
        LOOP
            /*add against star tar 361014 The NCR BOM Compare and Action List displays the Supply Location as an
internal Oracle ID and not the user defined location name so we take the segemnt1 i,e user defined location */   
                BEGIN

                      SELECT l.segment1
                      INTO   v_segment1 --user defined location name
               FROM   mtl_item_locations l
               WHERE l.organization_id = out_rec.organization_id 
                 AND   l.INVENTORY_LOCATION_ID=out_rec.wip_supply_locator_id
                 AND   l.subinventory_code =out_rec.wip_supply_subinventory;

  EXCEPTION
      WHEN OTHERS THEN
       v_err_msg :=SUBSTR(SQLERRM,1,50);
       v_err_code:=SQLCODE;
       FND_FILE.PUT_LINE(FND_FILE.LOG,v_err_code||': '||v_err_msg);
  END ; 
              
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
              v_orig_item                      ||'|'||
              v_orig_item_rev                  ||'|'||
              v_new_item                       ||'|'||
              v_new_item_rev                   ||'|'||
              out_rec.Action                   ||'|'||
              out_rec.COMP_ITEM_ID             ||'|'||
              out_rec.COMP_ITEM_REV            ||'|'||
              out_rec.DESCRIPTION              ||'|'||
              out_rec.PLANNER_CODE             ||'|'||
              out_rec.ACTION_QTY               ||'|'||
              out_rec.PAR_ITEM_ID              ||'|'||  -- RFC 1774
              out_rec.WIP_SUPPLY_SUBINVENTORY  ||'|'||
             -- out_rec.WIP_SUPPLY_LOCATOR_ID    ||'|'||
               v_segment1                 ||'|'|| --Display user defined location  
              out_rec.MAKE_BUY);

    END LOOP;

      
    ELSE
    -- Summary --

      -- Headers --
      FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
        'Original Product'       ||'|'||
        'Rev'                    ||'|'||
        'New Product'            ||'|'||
        'Rev'                    ||'|'||
        'Action'                 ||'|'||
        'Raw Material'           ||'|'||
        'Rev'                    ||'|'||
        'Description'            ||'|'||
        'Planner Code'           ||'|'||
        'Action Quantity');

      -- Data --
      --FOR out_rec in(SELECT * FROM NCR_EXPLODED_BOM_ITEMS)  --Commented for ERP-3127
        FOR out_rec in(SELECT * FROM NCR_EXPLODED_BOM_ITEMS WHERE SESSION_ID = v_session_id)  --Added for ERP-3127
        LOOP
            FND_FILE.PUT_LINE(FND_FILE.OUTPUT,
              v_orig_item                      ||'|'||
              v_orig_item_rev                  ||'|'||
              v_new_item                       ||'|'||
              v_new_item_rev                   ||'|'||
              out_rec.Action                   ||'|'||
              out_rec.COMP_ITEM_ID             ||'|'||
              out_rec.COMP_ITEM_REV            ||'|'||
              out_rec.DESCRIPTION              ||'|'||
              out_rec.PLANNER_CODE             ||'|'||
              out_rec.ACTION_QTY);
        END LOOP;

  END IF;

  END IF;

  -- Delete this Session's data from NCR_EXPLODED_BOM_ITEMS --
 DELETE FROM NCR_EXPLODED_BOM_ITEMS WHERE SESSION_ID = v_session_id;

  COMMIT;

EXCEPTION
    WHEN v_bompexpl_err THEN
      FND_FILE.PUT_LINE(FND_FILE.LOG,v_err_code||': '||v_err_msg);

    WHEN OTHERS THEN
      v_err_msg :=SUBSTR(SQLERRM,1,50);
      v_err_code:=SQLCODE;
      FND_FILE.PUT_LINE(FND_FILE.LOG,v_err_code||': '||v_err_msg);

END NCR_EXPLD_COMP_PROC;
/
show error
--exit
