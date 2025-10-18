-- Reference image viewer extension for Aseprite.
--
-- Copyright (c) 2025 enmarimo
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software
-- and associated documentation files (the “Software”), to deal in the Software without
-- restriction, including without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or
-- substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
-- BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
-- DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local ReferenceViewer = {}

-- Computes the scale factor that is needed to fit the Image into the GraphicsContext.
ReferenceViewer.getFittingScale = function(gc, image)
	local factor = gc.width / image.width
	local scaled_height = image.height * factor

	if(scaled_height > gc.height) then
		factor = gc.height / image.height
	end

	return factor
end

-- Updates the scale factor with the given delta taking into account lower and upper limits.
ReferenceViewer.updateZoom = function(scale_factor, delta)
	scale_factor = scale_factor + delta
	if scale_factor < 0.01 then
		scale_factor = 0.01
	elseif scale_factor > 2 then
		scale_factor = 2
	end

	return scale_factor
end

ReferenceViewer.createViewer = function(title)
	local dlg = Dialog(title)

	-- Active image, by default empty.
	-- We could try to store and restore the last opened image.
	local active_image = nil
	local active_image_filename = nil

	local fit_image = false

	local scale_factor = 1.0
	local inv_scale_factor = 1.0

	local image_pos = Point(0,0)
	local image_origin = Point(0,0)
	local mouse_origin = Point(0,0)
	local mouse_drag = false

	dlg:canvas{
		id="img_canvas",
		width=256,
		height=256,
		onpaint=function(ev)
			if active_image ~= nil then
				local gc = ev.context
				gc.antialias = true

				-- If the canvas size is 0 we don't need to draw
				-- anything.
				-- This should fix issue-1 as it prevents copying
				-- an empty (nil) image.
				-- The actual minimum size is 1 not 0 so, just in
				-- case, we avoid drawing when canvas size < 2.
				if gc.width < 2 or gc.height < 2 then
					return
				end

				local fit_scale = ReferenceViewer.getFittingScale(
					gc, active_image
				)

				if fit_image then
					-- Fit the image into the canvas: update scale_factor and restore
					-- the image position.
					-- Once done disable fit_image to make sure it is only called when
					-- requested.
					scale_factor = fit_scale

					if scale_factor < 0.01 then
						scale_factor = 0.01
					end

					inv_scale_factor = 1 / scale_factor

					image_pos = Point(0,0)
					fit_image = false
				end

				-- Updates the value of the slider with the actual value of scale_factor.
				dlg:modify{id="scale_slider", value=scale_factor*100}

                -- Clamp image position to avoid showing empty areas.
                local min_display_pixels = 2 * inv_scale_factor
                image_pos.x = math.max(image_pos.x, -gc.width * inv_scale_factor + min_display_pixels)
                image_pos.x = math.min(image_pos.x, active_image.width - min_display_pixels)
                image_pos.y = math.max(image_pos.y, -gc.height * inv_scale_factor + min_display_pixels)
                image_pos.y = math.min(image_pos.y, active_image.height - min_display_pixels)

				local image
				-- When we zoom-in (scale_factor > fit_scale) we only
				-- see a part of the image. We only copy what is visible
				-- and scale it to fit the window.
				-- When we zoom-out the image is fully visible, so
				-- we copy the whole image and scale it to the desired
				-- scale.
				if scale_factor > fit_scale then
					image = Image(
						active_image,
						Rectangle(
							image_pos.x, image_pos.y,
							gc.width * inv_scale_factor,
							gc.height * inv_scale_factor
						)
					)

					image:resize{
						width=gc.width, height=gc.height, method='bilinear'
					}

					gc:drawImage(
						image, 0, 0, image.width, image.height,
						0, 0, image.width, image.height
					)
				else
					image = Image(active_image)

					image:resize{
						width=active_image.width * scale_factor,
						height=active_image.height * scale_factor,
						method='bilinear'
					}

					-- Position has to be negative or it doesn't work as
					-- expected.
					-- TODO: Check why position is negative.
					--       This might need a refactor to make code
					--       easier to understand.
					gc:drawImage(
						image, 0, 0, image.width, image.height,
						-image_pos.x * scale_factor,
						-image_pos.y * scale_factor,
						image.width, image.height
					)
				end
			end
		end,
		onwheel=function(ev)
			-- Update the scale_factor when using the mouse wheel.
			-- Tested on a laptop it works with deltaY, it should be tested on actual mouse.
			local wheel_factor = 0.05

			-- Get the relative position of mouse respect to the image.
			-- I would expect dx should be (ev.x - image_pos.x), but image_pos.x seems inverted
			-- (positive values when image goes to the left and negative to the right) so it has
			-- to be inverted here to work as expected.
			local dx = ev.x * inv_scale_factor + image_pos.x
			local dy = ev.y * inv_scale_factor + image_pos.y

			if ev.deltaY > 0 then
				scale_factor = ReferenceViewer.updateZoom(
					scale_factor, -wheel_factor
				)
			else
				scale_factor = ReferenceViewer.updateZoom(
					scale_factor, wheel_factor
				)
			end

			-- Keep the relative position between the mouse and image. This way, when we zoom the
			-- image it will keep centered at the point we are zooming.
			inv_scale_factor = 1 / scale_factor
			image_pos.x = -ev.x * inv_scale_factor + dx
			image_pos.y = -ev.y * inv_scale_factor + dy

			-- Redraw the canvas with the updated scale_factor.
			dlg:repaint()
		end,
		-- touch works weird, for now disable it.
		--ontouchmagnify=function(ev)
		--	scale_factor = zoom(scale_factor, ev.magnification)
		--	dlg:repaint()
		--end,
		onmousedown=function(ev)
			-- When using the eyedropper (color-picker) get the color of the
			-- clicked pixel on the image.
			-- Otherwise, prepare to move the image.
			if app.tool.id == "eyedropper" then
				if active_image ~= nil then
					if scale_factor >= 0.01 then

						local pixel = active_image:getPixel(
							ev.x * inv_scale_factor + image_pos.x,
							ev.y * inv_scale_factor + image_pos.y
						);

						if ev.button == MouseButton.LEFT then
							app.fgColor = Color(pixel)
						elseif ev.button == MouseButton.RIGHT then
							app.bgColor = Color(pixel)
						end
					end
				end
			else
				mouse_drag = true
				mouse_origin = Point(ev.x, ev.y)
				image_origin = image_pos
			end
		end,
		onmouseup=function(ev)
			mouse_drag = false
		end,
		onmousemove=function(ev)
			if mouse_drag then
				local mouse = Point(ev.x, ev.y)
				local dpos = Point(
					(mouse.x - mouse_origin.x) * inv_scale_factor,
					(mouse.y - mouse_origin.y) * inv_scale_factor
				)
				image_pos = image_origin - dpos
				dlg:repaint()
			end
		end,
		onkeydown=function(ev)
			if ev.ctrlKey then
				-- When Ctrl-V, load the clipboard image.
				-- Stop propagation of the event to prevent the image
				-- being pasted on the main canvas.
				ev:stopPropagation()

				if ev.code == "KeyV" then
					if app.apiVersion >= 32 and app.clipboard.image ~= nil then
						active_image = app.clipboard.image

						-- When an image is loaded, show the hidden controls
						dlg:modify{id="scale_slider", visible=true}
						dlg:modify{id="fit_button", visible=true}

						-- redraw the canvas
						dlg:repaint()
					end
				end
			end
		end
	}
	dlg:slider{
		id="scale_slider",
		min=0,
		max=200,
		value=100,
		visible=false,
		onchange=function()
			scale_factor = dlg.data.scale_slider / 100

			if scale_factor < 0.01 then
				scale_factor = 0.01
			end

			inv_scale_factor = 1 / scale_factor

			dlg:repaint()
		end
	}
	dlg:button{
		id="fit_button",
		text="Fit",
		visible=false,
		onclick=function()
			fit_image = true
			dlg:repaint()
		end
	}
	dlg:file{
		id="img_file",
		open=true,
		save=false,
		onchange=function()
			-- When the file widget changes we want to open the selected image and draw it on
			-- the canvas.
			-- TODO: Check the file is actually an image.

			local image_filename = dlg.data.img_file
			-- Print used for testing.
			-- print("Image: " .. image_file)

			-- If the image changed, update it.
			-- TODO: Is this check really needed?
			if image_filename ~= active_image_filename then
				active_image_filename = image_filename
				active_image = Image{fromFile=active_image_filename}

				-- When an image is loaded, show the hidden controls
				dlg:modify{id="scale_slider", visible=true}
				dlg:modify{id="fit_button", visible=true}

				-- redraw the canvas
				dlg:repaint()
			end
		end
	}

	dlg:show{wait=false}
end

return ReferenceViewer
